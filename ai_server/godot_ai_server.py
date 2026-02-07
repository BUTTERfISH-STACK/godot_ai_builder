#!/usr/bin/env python3
"""
Godot 4 Autonomous AI Builder - Local AI Control Server
=======================================================
Local WebSocket server that communicates with the Godot Editor Plugin
to enable AI-driven game development.

Features:
- WebSocket communication with Godot Editor Plugin
- Command dispatching and retry logic
- Performance monitoring integration
- Self-correcting error handling loop
"""

import asyncio
import json
import logging
import sys
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Callable
from dataclasses import dataclass, field
from enum import Enum
import websockets
from websockets.server import WebSocketServerProtocol
import traceback

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("AI_Control_Server")


class CommandType(Enum):
    """Supported command types."""
    CREATE_SCENE = "create_scene"
    ADD_NODE = "add_node"
    SET_PROPERTY = "set_property"
    ATTACH_SCRIPT = "attach_script"
    CREATE_SCRIPT = "create_script"
    MODIFY_SCRIPT = "modify_script"
    DELETE_NODE = "delete_node"
    RUN_SCENE = "run_scene"
    SAVE_SCENE = "save_scene"
    GET_SNAPSHOT = "get_snapshot"
    GET_PERFORMANCE = "get_performance"
    RETRY = "retry"
    GET_STATUS = "get_status"
    GET_PROTOCOL = "get_protocol"


@dataclass
class Command:
    """Represents a command to be sent to the Godot Editor."""
    action: str
    parameters: Dict[str, Any] = field(default_factory=dict)
    auto_run: bool = False
    request_id: str = ""
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert command to dictionary."""
        result = {
            "action": self.action,
            "auto_run": self.auto_run
        }
        result.update(self.parameters)
        if self.request_id:
            result["request_id"] = self.request_id
        return result
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Command':
        """Create command from dictionary."""
        return cls(
            action=data.get("action", ""),
            parameters={k: v for k, v in data.items() if k not in ["action", "auto_run", "request_id"]},
            auto_run=data.get("auto_run", False),
            request_id=data.get("request_id", "")
        )


@dataclass
class Response:
    """Represents a response from the Godot Editor."""
    status: str
    action: str = ""
    error: str = ""
    error_type: str = ""
    error_details: Dict[str, Any] = field(default_factory=dict)
    data: Dict[str, Any] = field(default_factory=dict)
    timestamp: float = 0.0
    
    def is_success(self) -> bool:
        """Check if response indicates success."""
        return self.status == "success"
    
    def is_error(self) -> bool:
        """Check if response indicates an error."""
        return self.status == "error"
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert response to dictionary."""
        result = {"status": self.status}
        if self.action:
            result["action"] = self.action
        if self.error:
            result["error"] = self.error
        if self.error_type:
            result["error_type"] = self.error_type
        if self.error_details:
            result["error_details"] = self.error_details
        result.update(self.data)
        return result
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Response':
        """Create response from dictionary."""
        return cls(
            status=data.get("status", "unknown"),
            action=data.get("action", ""),
            error=data.get("error", ""),
            error_type=data.get("type", ""),
            error_details=data.get("error_details", {}),
            data={k: v for k, v in data.items() if k not in ["status", "action", "error", "type", "error_details"]},
            timestamp=data.get("timestamp", 0.0)
        )


class RetryEngine:
    """Handles retry logic for failed commands."""
    
    MAX_RETRIES = 5
    RETRY_DELAY_BASE = 1.0  # Base delay in seconds
    RETRY_DELAY_MAX = 10.0  # Maximum delay
    
    def __init__(self):
        self.retry_count: Dict[str, int] = {}
        self.retry_history: List[Dict] = []
    
    def should_retry(self, request_id: str) -> bool:
        """Check if a command should be retried."""
        count = self.retry_count.get(request_id, 0)
        return count < self.MAX_RETRIES
    
    def get_retry_delay(self, request_id: str) -> float:
        """Calculate delay for next retry (exponential backoff)."""
        count = self.retry_count.get(request_id, 0)
        delay = self.RETRY_DELAY_BASE * (2 ** count)
        return min(delay, self.RETRY_DELAY_MAX)
    
    def record_attempt(self, request_id: str, command: Command, response: Response) -> None:
        """Record a retry attempt."""
        if request_id not in self.retry_count:
            self.retry_count[request_id] = 0
        
        self.retry_count[request_id] += 1
        
        self.retry_history.append({
            "request_id": request_id,
            "command": command.to_dict(),
            "response": response.to_dict(),
            "attempt": self.retry_count[request_id],
            "timestamp": datetime.now().isoformat()
        })
        
        logger.info(f"Retry attempt {self.retry_count[request_id]} for {request_id}")
    
    def reset(self, request_id: str) -> None:
        """Reset retry counter for a request."""
        if request_id in self.retry_count:
            del self.retry_count[request_id]
    
    def can_continue(self, request_id: str) -> bool:
        """Check if we should continue retrying."""
        return self.should_retry(request_id)
    
    def get_retry_info(self, request_id: str) -> Dict[str, Any]:
        """Get retry information for a request."""
        return {
            "request_id": request_id,
            "current_attempt": self.retry_count.get(request_id, 0),
            "max_attempts": self.MAX_RETRIES,
            "can_retry": self.should_retry(request_id)
        }


class PerformanceAnalyzer:
    """Analyzes performance reports from Godot."""
    
    THRESHOLDS = {
        "fps_min": 30.0,
        "fps_warning": 45.0,
        "draw_calls_max": 5000,
        "draw_calls_warning": 3000,
        "node_count_max": 2000,
        "node_count_warning": 1500,
        "memory_max_mb": 512.0
    }
    
    def analyze(self, report: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze a performance report."""
        analysis = {
            "status": "ok",
            "issues": [],
            "warnings": [],
            "recommendations": []
        }
        
        fps = report.get("fps", 60.0)
        draw_calls = report.get("draw_calls", 0)
        node_count = report.get("node_count", 0)
        memory_mb = report.get("memory_usage_mb", 0.0)
        
        # Check FPS
        if fps < self.THRESHOLDS["fps_min"]:
            analysis["status"] = "critical"
            analysis["issues"].append({
                "metric": "fps",
                "value": fps,
                "threshold": self.THRESHOLDS["fps_min"],
                "message": f"Critical FPS: {fps:.1f}"
            })
        elif fps < self.THRESHOLDS["fps_warning"]:
            analysis["warnings"].append({
                "metric": "fps",
                "value": fps,
                "threshold": self.THRESHOLDS["fps_warning"],
                "message": f"Low FPS: {fps:.1f}"
            })
        
        # Check draw calls
        if draw_calls > self.THRESHOLDS["draw_calls_max"]:
            analysis["status"] = "critical" if analysis["status"] != "critical" else "critical"
            analysis["issues"].append({
                "metric": "draw_calls",
                "value": draw_calls,
                "threshold": self.THRESHOLDS["draw_calls_max"],
                "message": f"Critical draw calls: {draw_calls}"
            })
        elif draw_calls > self.THRESHOLDS["draw_calls_warning"]:
            if "warning" not in analysis["status"]:
                analysis["warnings"].append({
                    "metric": "draw_calls",
                    "value": draw_calls,
                    "threshold": self.THRESHOLDS["draw_calls_warning"],
                    "message": f"High draw calls: {draw_calls}"
                })
        
        # Check node count
        if node_count > self.THRESHOLDS["node_count_max"]:
            analysis["status"] = "critical" if analysis["status"] != "critical" else "critical"
            analysis["issues"].append({
                "metric": "node_count",
                "value": node_count,
                "threshold": self.THRESHOLDS["node_count_max"],
                "message": f"Critical node count: {node_count}"
            })
        elif node_count > self.THRESHOLDS["node_count_warning"]:
            analysis["warnings"].append({
                "metric": "node_count",
                "value": node_count,
                "threshold": self.THRESHOLDS["node_count_warning"],
                "message": f"High node count: {node_count}"
            })
        
        # Generate recommendations
        analysis["recommendations"] = self._generate_recommendations(analysis)
        
        return analysis
    
    def _generate_recommendations(self, analysis: Dict[str, Any]) -> List[Dict[str, str]]:
        """Generate optimization recommendations."""
        recommendations = []
        
        for issue in analysis.get("issues", []):
            if issue["metric"] == "fps":
                recommendations.append({
                    "priority": "high",
                    "area": "frame_rate",
                    "message": "Reduce shader complexity, implement LOD, enable occlusion culling"
                })
            elif issue["metric"] == "draw_calls":
                recommendations.append({
                    "priority": "high",
                    "area": "draw_calls",
                    "message": "Use MultiMeshInstance, enable GPU instancing, combine static meshes"
                })
            elif issue["metric"] == "node_count":
                recommendations.append({
                    "priority": "high",
                    "area": "node_count",
                    "message": "Merge static geometry, implement object pooling"
                })
        
        for warning in analysis.get("warnings", []):
            recommendations.append({
                "priority": "medium",
                "area": warning["metric"],
                "message": f"Monitor {warning['metric']} - current: {warning['value']}"
            })
        
        return recommendations


class GodotAIClient:
    """Manages WebSocket connection to Godot Editor Plugin."""
    
    DEFAULT_PORT = 8765
    RECONNECT_DELAY = 2.0
    PING_INTERVAL = 5.0
    PING_TIMEOUT = 10.0
    
    def __init__(self, host: str = "localhost", port: int = None):
        self.host = host
        self.port = port or self.DEFAULT_PORT
        self.websocket: Optional[WebSocketServerProtocol] = None
        self.connected = False
        self.reconnect_task: Optional[asyncio.Task] = None
        self.message_handlers: List[Callable] = []
    
    async def connect(self) -> bool:
        """Establish WebSocket connection to Godot."""
        try:
            uri = f"ws://{self.host}:{self.port}"
            self.websocket = await websockets.connect(
                uri,
                ping_interval=self.PING_INTERVAL,
                ping_timeout=self.PING_TIMEOUT
            )
            self.connected = True
            logger.info(f"Connected to Godot Editor at {uri}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Godot: {e}")
            self.connected = False
            return False
    
    async def disconnect(self) -> None:
        """Close WebSocket connection."""
        if self.websocket:
            await self.websocket.close()
            self.websocket = None
        self.connected = False
        logger.info("Disconnected from Godot Editor")
    
    async def send_command(self, command: Command) -> Optional[Response]:
        """Send a command to Godot and wait for response."""
        if not self.connected or not self.websocket:
            logger.error("Not connected to Godot Editor")
            return None
        
        try:
            message = json.dumps(command.to_dict())
            await self.websocket.send(message)
            logger.debug(f"Sent command: {command.action}")
            
            # Wait for response
            response_data = await asyncio.wait_for(
                self.websocket.recv(),
                timeout=30.0
            )
            
            response_dict = json.loads(response_data)
            response = Response.from_dict(response_dict)
            
            logger.debug(f"Received response: {response.status}")
            return response
            
        except asyncio.TimeoutError:
            logger.error("Timeout waiting for response")
            return None
        except Exception as e:
            logger.error(f"Error sending command: {e}")
            return None
    
    async def receive_messages(self) -> None:
        """Continuously receive messages from Godot."""
        try:
            async for message in self.websocket:
                try:
                    data = json.loads(message)
                    for handler in self.message_handlers:
                        handler(data)
                except json.JSONDecodeError:
                    logger.warning(f"Invalid JSON received: {message}")
        except websockets.exceptions.ConnectionClosed:
            logger.warning("Connection to Godot closed")
            self.connected = False
    
    def add_message_handler(self, handler: Callable) -> None:
        """Add a message handler."""
        self.message_handlers.append(handler)
    
    def remove_message_handler(self, handler: Callable) -> None:
        """Remove a message handler."""
        if handler in self.message_handlers:
            self.message_handlers.remove(handler)
    
    async def reconnect_loop(self) -> None:
        """Attempt to reconnect to Godot."""
        while not self.connected:
            logger.info(f"Attempting to reconnect to Godot...")
            if await self.connect():
                break
            await asyncio.sleep(self.RECONNECT_DELAY)


class AICommandDispatcher:
    """Dispatches commands to Godot and handles responses."""
    
    def __init__(self, client: GodotAIClient):
        self.client = client
        self.retry_engine = RetryEngine()
        self.performance_analyzer = PerformanceAnalyzer()
        self.pending_commands: Dict[str, Command] = {}
        self.command_history: List[Dict] = []
    
    async def execute_command(self, command: Command, max_retries: int = None) -> Response:
        """Execute a command with retry logic."""
        request_id = command.request_id or self._generate_request_id()
        command.request_id = request_id
        
        self.pending_commands[request_id] = command
        
        attempts = 0
        while True:
            attempts += 1
            
            response = await self.client.send_command(command)
            
            if response is None:
                # Communication error
                if self.retry_engine.can_continue(request_id):
                    delay = self.retry_engine.get_retry_delay(request_id)
                    await asyncio.sleep(delay)
                    continue
                else:
                    return Response(
                        status="error",
                        error="Failed to communicate with Godot Editor",
                        error_type="communication"
                    )
            
            # Record the attempt
            self.retry_engine.record_attempt(request_id, command, response)
            
            # Check response
            if response.is_success():
                self._log_command(command, response, attempts)
                self.retry_engine.reset(request_id)
                return response
            
            if response.is_error():
                error_type = response.error_type
                
                # Check if we should retry
                if error_type in ["compile", "runtime"] and self.retry_engine.can_continue(request_id):
                    delay = self.retry_engine.get_retry_delay(request_id)
                    logger.info(f"Retrying after {delay}s (attempt {attempts})")
                    await asyncio.sleep(delay)
                    continue
                else:
                    # Don't retry other error types
                    self._log_command(command, response, attempts)
                    return response
        
        self.pending_commands.pop(request_id, None)
        return Response(status="error", error="Unexpected exit from command loop")
    
    async def execute_batch(self, commands: List[Command]) -> List[Response]:
        """Execute multiple commands sequentially."""
        results = []
        for command in commands:
            response = await self.execute_command(command)
            results.append(response)
            if response.is_error():
                # Stop on first error in batch
                break
        return results
    
    def analyze_performance(self, report: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze a performance report."""
        return self.performance_analyzer.analyze(report)
    
    def get_retry_info(self, request_id: str) -> Dict[str, Any]:
        """Get retry information."""
        return self.retry_engine.get_retry_info(request_id)
    
    def _generate_request_id(self) -> str:
        """Generate a unique request ID."""
        import uuid
        return f"req_{uuid.uuid4().hex[:8]}"
    
    def _log_command(self, command: Command, response: Response, attempts: int) -> None:
        """Log command execution."""
        entry = {
            "command": command.to_dict(),
            "response": response.to_dict(),
            "attempts": attempts,
            "timestamp": datetime.now().isoformat()
        }
        self.command_history.append(entry)
        
        if len(self.command_history) > 1000:
            self.command_history = self.command_history[-1000:]
        
        if response.is_success():
            logger.info(f"Command '{command.action}' succeeded in {attempts} attempt(s)")
        else:
            logger.error(f"Command '{command.action}' failed: {response.error}")


class GameBuilder:
    """High-level API for building games with AI."""
    
    def __init__(self, host: str = "localhost", port: int = 8765):
        self.client = GodotAIClient(host, port)
        self.dispatcher = AICommandDispatcher(self.client)
        self.game_state: Dict[str, Any] = {}
    
    async def connect(self) -> bool:
        """Connect to Godot Editor."""
        return await self.client.connect()
    
    async def disconnect(self) -> None:
        """Disconnect from Godot Editor."""
        await self.client.disconnect()
    
    async def create_game(self, description: str) -> Dict[str, Any]:
        """
        Create a game based on a natural language description.
        
        Args:
            description: Natural language description of the game
        
        Returns:
            Dictionary with creation results
        """
        result = {
            "description": description,
            "success": False,
            "actions": [],
            "errors": []
        }
        
        # Parse the description into commands
        commands = self._parse_game_description(description)
        
        # Execute commands
        for command in commands:
            response = await self.dispatcher.execute_command(command, max_retries=5)
            result["actions"].append({
                "command": command.to_dict(),
                "response": response.to_dict()
            })
            
            if response.is_error():
                result["errors"].append({
                    "command": command.to_dict(),
                    "error": response.error
                })
                break
        
        result["success"] = len(result["errors"]) == 0
        return result
    
    def _parse_game_description(self, description: str) -> List[Command]:
        """Parse a natural language description into commands."""
        commands = []
        
        description = description.lower()
        
        # Detect game type
        if "third-person" in description:
            if "survival" in description:
                commands.append(Command(
                    action="create_scene",
                    parameters={
                        "name": "MainScene",
                        "scene_type": "Node3D",
                        "save_path": "res://scenes/main.tscn"
                    },
                    auto_run=True
                ))
                
                # Add player character
                commands.append(Command(
                    action="add_node",
                    parameters={
                        "node_type": "CharacterBody3D",
                        "parent_path": "/root/MainScene",
                        "name": "Player",
                        "position": [0, 1, 0]
                    }
                ))
                
                # Add camera
                commands.append(Command(
                    action="add_node",
                    parameters={
                        "node_type": "Camera3D",
                        "parent_path": "/root/MainScene/Player",
                        "name": "Camera3D",
                        "position": [0, 2, 3]
                    }
                ))
                
                # Add inventory system (placeholder script)
                commands.append(Command(
                    action="create_script",
                    parameters={
                        "path": "res://scripts/inventory.gd",
                        "name": "Inventory",
                        "base_class": "Node"
                    }
                ))
        
        # Add scene runner
        commands.append(Command(
            action="run_scene",
            parameters={
                "scene_path": "res://scenes/main.tscn"
            },
            auto_run=False
        ))
        
        return commands
    
    async def add_player_character(self, scene_path: str, position: List[float] = [0, 1, 0]) -> Response:
        """Add a player character to a scene."""
        return await self.dispatcher.execute_command(Command(
            action="add_node",
            parameters={
                "node_type": "CharacterBody3D",
                "parent_path": f"/root/{Path(scene_path).stem}",
                "name": "Player",
                "position": position
            }
        ))
    
    async def add_camera(self, parent_path: str, position: List[float] = [0, 2, 3]) -> Response:
        """Add a camera to a node."""
        return await self.dispatcher.execute_command(Command(
            action="add_node",
            parameters={
                "node_type": "Camera3D",
                "parent_path": parent_path,
                "name": "Camera3D",
                "position": position
            }
        ))
    
    async def add_light(self, parent_path: str, light_type: str = "DirectionalLight3D") -> Response:
        """Add a light to a node."""
        return await self.dispatcher.execute_command(Command(
            action="add_node",
            parameters={
                "node_type": light_type,
                "parent_path": parent_path,
                "name": "Light",
                "rotation": [-45, 45, 0]
            }
        ))
    
    async def get_scene_snapshot(self) -> Dict[str, Any]:
        """Get the current scene snapshot."""
        response = await self.dispatcher.execute_command(Command(
            action="get_snapshot"
        ))
        if response and response.is_success():
            return response.data
        return {}
    
    async def get_performance_report(self) -> Dict[str, Any]:
        """Get performance metrics."""
        response = await self.dispatcher.execute_command(Command(
            action="get_performance"
        ))
        if response and response.is_success():
            return response.data
        return {}


async def main():
    """Main entry point for the AI Control Server."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Godot AI Builder Control Server")
    parser.add_argument("--host", default="localhost", help="Godot Editor host")
    parser.add_argument("--port", type=int, default=8765, help="WebSocket port")
    parser.add_argument("--mode", choices=["server", "builder"], default="builder",
                        help="Run mode: server (WebSocket) or builder (direct)")
    args = parser.parse_args()
    
    if args.mode == "builder":
        # Direct builder mode
        builder = GameBuilder(args.host, args.port)
        
        if await builder.connect():
            logger.info("Connected to Godot Editor")
            
            # Example: Create a simple game
            response = await builder.create_game("Create a third-person survival game with inventory")
            logger.info(f"Game creation result: {response}")
            
            await builder.disconnect()
        else:
            logger.error("Failed to connect to Godot Editor")
    
    else:
        # WebSocket server mode
        # This would run a WebSocket server for external AI connections
        logger.info(f"Starting AI Control Server on port {args.port}")
        # Implementation would go here
        
        # Keep running
        while True:
            await asyncio.sleep(1.0)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}")
        traceback.print_exc()
