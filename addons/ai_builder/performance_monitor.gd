@tool
extends Node

## Performance Monitor for Godot AI Builder
## ========================================
## Monitors and reports performance metrics during runtime.

# Signal declarations
signal performance_report(report: Dictionary)
signal performance_warning(warning: Dictionary)
signal performance_critical(critical: Dictionary)

# Monitoring state
var _is_monitoring: bool = false
var _monitoring_start_time: float = 0.0
var _report_interval: float = 1.0  # Report every second
var _last_report_time: float = 0.0

# Performance thresholds
const THRESHOLDS: Dictionary = {
	"fps_min": 30.0,
	"fps_warning": 45.0,
	"draw_calls_max": 5000,
	"draw_calls_warning": 3000,
	"node_count_max": 2000,
	"node_count_warning": 1500,
	"memory_max_mb": 512.0,
	"physics_time_max_ms": 16.0
}

# Metrics history
var _metrics_history: Array[Dictionary] = []
const MAX_HISTORY: int = 300  # 5 minutes at 1 sample/second


## Lifecycle
## ========

func _ready() -> void:
	"""
	Initialize the performance monitor.
	"""
	print("[Performance Monitor] Initialized")


func _process(_delta: float) -> void:
	"""
	Process performance monitoring.
	"""
	if not _is_monitoring:
		return
	
	var current_time: float = Time.get_unix_time_from_system()
	
	if current_time - _last_report_time >= _report_interval:
		_collect_and_report()


## Public Methods
## =============

func start_monitoring(interval: float = 1.0) -> void:
	"""
	Starts performance monitoring.
	
	Args:
		interval: Report interval in seconds
	"""
	_is_monitoring = true
	_monitoring_start_time = Time.get_unix_time_from_system()
	_report_interval = interval
	_last_report_time = Time.get_unix_time_from_system()
	
	print("[Performance Monitor] Started monitoring (interval: %s s)" % interval)


func stop_monitoring() -> void:
	"""
	Stops performance monitoring.
	"""
	_is_monitoring = false
	print("[Performance Monitor] Stopped monitoring")


func is_active() -> bool:
	"""
	Returns whether monitoring is active.
	"""
	return _is_monitoring


func get_report() -> Dictionary:
	"""
	Returns the current performance report.
	"""
	return _collect_metrics()


func get_history(count: int = 60) -> Array:
	"""
	Returns performance history.
	
	Args:
		count: Number of samples to return
	
	Returns:
		Array of performance reports
	"""
	var result: Array = _metrics_history.duplicate()
	
	if count < result.size():
		return result.slice(-count)
	
	return result


func clear_history() -> void:
	"""
	Clears performance history.
	"""
	_metrics_history.clear()
	print("[Performance Monitor] History cleared")


## Internal Methods
## ==============

func _collect_and_report() -> void:
	"""
	Collects metrics and sends a report.
	"""
	var report: Dictionary = _collect_metrics()
	
	# Store in history
	_metrics_history.append(report)
	
	# Trim history if too large
	if _metrics_history.size() > MAX_HISTORY:
		_metrics_history = _metrics_history.slice(-MAX_HISTORY)
	
	_last_report_time = Time.get_unix_time_from_system()
	
	# Check thresholds and emit warnings
	_check_thresholds(report)
	
	# Emit report signal
	performance_report.emit(report)


func _collect_metrics() -> Dictionary:
	"""
	Collects current performance metrics.
	"""
	var metrics: Dictionary = {
		"timestamp": Time.get_unix_time_from_system(),
		"uptime": Time.get_unix_time_from_system() - _monitoring_start_time,
		"fps": 0.0,
		"draw_calls": 0,
		"node_count": 0,
		"memory_usage_mb": 0.0,
		"physics_time_ms": 0.0,
		"render_time_ms": 0.0,
		"process_time_ms": 0.0
	}
	
	# Get FPS
	metrics["fps"] = Engine.get_frames_per_second()
	
	# Get rendering info
	var rendering_server: RenderingServer = RenderingServer
	if rendering_server != null:
		metrics["draw_calls"] = rendering_server.get_rendering_info(RenderingServer.RENDERING_INFO_DRAW_CALLS)
	
	# Get node count
	var tree: SceneTree = get_tree()
	if tree != null:
		metrics["node_count"] = _count_nodes(tree.get_root())
	
	# Get memory usage
	var memory_info: Dictionary = OS.get_memory_info()
	metrics["memory_usage_mb"] = memory_info.get("used", 0) / (1024.0 * 1024.0)
	
	# Get performance time
	metrics["physics_time_ms"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	metrics["render_time_ms"] = Performance.get_monitor(Performance.TIME_RENDER_PROCESS) * 1000.0
	metrics["process_time_ms"] = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	
	return metrics


func _count_nodes(root: Node) -> int:
	"""
	Counts all nodes in the tree.
	"""
	var count: int = 0
	
	if root == null:
		return 0
	
	count = 1  # Count the root
	
	for child: Node in root.get_children():
		count += _count_nodes(child)
	
	return count


func _check_thresholds(report: Dictionary) -> void:
	"""
	Checks performance against thresholds.
	"""
	var warnings: Array = []
	var critical: Array = []
	
	var fps: float = report.get("fps", 60.0)
	var draw_calls: int = report.get("draw_calls", 0)
	var node_count: int = report.get("node_count", 0)
	var memory: float = report.get("memory_usage_mb", 0.0)
	var physics_time: float = report.get("physics_time_ms", 0.0)
	
	# Check FPS
	if fps < THRESHOLDS.fps_min:
		critical.append({
			"metric": "fps",
			"value": fps,
			"threshold": THRESHOLDS.fps_min,
			"message": "FPS critically low: %.1f" % fps
		})
	elif fps < THRESHOLDS.fps_warning:
		warnings.append({
			"metric": "fps",
			"value": fps,
			"threshold": THRESHOLDS.fps_warning,
			"message": "FPS below optimal: %.1f" % fps
		})
	
	# Check draw calls
	if draw_calls > THRESHOLDS.draw_calls_max:
		critical.append({
			"metric": "draw_calls",
			"value": draw_calls,
			"threshold": THRESHOLDS.draw_calls_max,
			"message": "Draw calls critically high: %d" % draw_calls
		})
	elif draw_calls > THRESHOLDS.draw_calls_warning:
		warnings.append({
			"metric": "draw_calls",
			"value": draw_calls,
			"threshold": THRESHOLDS.draw_calls_warning,
			"message": "Draw calls high: %d" % draw_calls
		})
	
	# Check node count
	if node_count > THRESHOLDS.node_count_max:
		critical.append({
			"metric": "node_count",
			"value": node_count,
			"threshold": THRESHOLDS.node_count_max,
			"message": "Node count critically high: %d" % node_count
		})
	elif node_count > THRESHOLDS.node_count_warning:
		warnings.append({
			"metric": "node_count",
			"value": node_count,
			"threshold": THRESHOLDS.node_count_warning,
			"message": "Node count high: %d" % node_count
		})
	
	# Check memory
	if memory > THRESHOLDS.memory_max_mb:
		critical.append({
			"metric": "memory",
			"value": memory,
			"threshold": THRESHOLDS.memory_max_mb,
			"message": "Memory usage critically high: %.1f MB" % memory
		})
	
	# Check physics time
	if physics_time > THRESHOLDS.physics_time_max_ms * 2:
		warnings.append({
			"metric": "physics_time",
			"value": physics_time,
			"threshold": THRESHOLDS.physics_time_max_ms,
			"message": "Physics time high: %.2f ms" % physics_time
		})
	
	# Emit warnings
	if not warnings.is_empty():
		var warning_report: Dictionary = {
			"type": "warning",
			"timestamp": report["timestamp"],
			"warnings": warnings
		}
		performance_warning.emit(warning_report)
	
	# Emit critical
	if not critical.is_empty():
		var critical_report: Dictionary = {
			"type": "critical",
			"timestamp": report["timestamp"],
			"issues": critical
		}
		performance_critical.emit(critical_report)


## Utility Methods
## ==============

func get_thresholds() -> Dictionary:
	"""
	Returns the performance thresholds.
	"""
	return THRESHOLDS.duplicate()


func set_threshold(metric: String, value: Variant) -> void:
	"""
	Sets a performance threshold.
	
	Args:
		metric: Metric name
		value: New threshold value
	"""
	if THRESHOLDS.has(metric):
		THRESHOLDS[metric] = value
		print("[Performance Monitor] Threshold '%s' set to %s" % [metric, str(value)])


func get_statistics() -> Dictionary:
	"""
	Returns performance statistics from history.
	"""
	var stats: Dictionary = {
		"samples": _metrics_history.size(),
		"uptime_seconds": 0.0,
		"fps": {"min": 999.0, "max": 0.0, "avg": 0.0},
		"draw_calls": {"min": 999999, "max": 0, "avg": 0.0},
		"node_count": {"min": 999999, "max": 0, "avg": 0.0},
		"memory_mb": {"min": 9999.0, "max": 0.0, "avg": 0.0}
	}
	
	if _metrics_history.is_empty():
		return stats
	
	var fps_sum: float = 0.0
	var draw_sum: float = 0.0
	var node_sum: float = 0.0
	var mem_sum: float = 0.0
	
	var last_timestamp: float = 0.0
	
	for sample: Dictionary in _metrics_history:
		var fps: float = sample.get("fps", 0.0)
		var draw: int = sample.get("draw_calls", 0)
		var nodes: int = sample.get("node_count", 0)
		var mem: float = sample.get("memory_usage_mb", 0.0)
		
		# Update min/max
		stats["fps"]["min"] = min(stats["fps"]["min"], fps)
		stats["fps"]["max"] = max(stats["fps"]["max"], fps)
		
		stats["draw_calls"]["min"] = min(stats["draw_calls"]["min"], draw)
		stats["draw_calls"]["max"] = max(stats["draw_calls"]["max"], draw)
		
		stats["node_count"]["min"] = min(stats["node_count"]["min"], nodes)
		stats["node_count"]["max"] = max(stats["node_count"]["max"], nodes)
		
		stats["memory_mb"]["min"] = min(stats["memory_mb"]["min"], mem)
		stats["memory_mb"]["max"] = max(stats["memory_mb"]["max"], mem)
		
		# Sum for average
		fps_sum += fps
		draw_sum += draw
		node_sum += nodes
		mem_sum += mem
		
		# Track uptime
		var timestamp: float = sample.get("timestamp", 0.0)
		if timestamp > last_timestamp:
			last_timestamp = timestamp
	
	var sample_count: float = float(_metrics_history.size())
	
	stats["uptime_seconds"] = last_timestamp - _monitoring_start_time
	
	stats["fps"]["avg"] = fps_sum / sample_count
	stats["draw_calls"]["avg"] = draw_sum / sample_count
	stats["node_count"]["avg"] = node_sum / sample_count
	stats["memory_mb"]["avg"] = mem_sum / sample_count
	
	return stats


func generate_optimization_recommendations() -> Array:
	"""
	Generates optimization recommendations based on collected metrics.
	"""
	var recommendations: Array = []
	var stats: Dictionary = get_statistics()
	
	# FPS recommendations
	if stats["fps"]["avg"] < 50.0:
		recommendations.append({
			"priority": "high",
			"area": "frame_rate",
			"message": "Average FPS is below 50",
			"solutions": [
				"Reduce shader complexity",
				"Implement level-of-detail (LOD) systems",
				"Optimize draw calls with batching",
				"Reduce overdraw with occlusion culling"
			]
		})
	
	# Draw call recommendations
	if stats["draw_calls"]["avg"] > 2000:
		recommendations.append({
			"priority": "high",
			"area": "draw_calls",
			"message": "Average draw calls exceed 2000",
			"solutions": [
				"Use MultiMeshInstance for repeated objects",
				"Enable GPU instancing for meshes",
				"Combine static meshes into single meshes",
				"Use texture atlases to reduce material switches"
			]
		})
	
	# Node count recommendations
	if stats["node_count"]["avg"] > 1000:
		recommendations.append({
			"priority": "medium",
			"area": "node_count",
			"message": "Average node count exceeds 1000",
			"solutions": [
				"Merge static geometry into single meshes",
				"Use MultiMeshInstance for repeated objects",
				"Implement object pooling for dynamic objects",
				"Reduce unnecessary child nodes"
			]
		})
	
	# Memory recommendations
	if stats["memory_mb"]["avg"] > 256.0:
		recommendations.append({
			"priority": "medium",
			"area": "memory",
			"message": "Average memory usage exceeds 256 MB",
			"solutions": [
				"Implement texture compression",
				"Unload unused resources",
				"Use resource preloading with unloading",
				"Optimize audio file sizes"
			]
		})
	
	return recommendations
