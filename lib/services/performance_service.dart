import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Mirrors iOS `AppPerformanceTracing` enum + `PerformanceMonitoringService`.
///
/// iOS reference:
///   Services/AppPerformanceTracing.swift — startTrace/stopTrace
///   Services/PerformanceMonitoringService.swift — setupPerformanceMonitoring
///
/// Usage:
/// ```dart
/// final trace = await PPPerformance.startTrace('property_list_load');
/// // ... do work ...
/// await PPPerformance.stopTrace(trace);
/// ```
class PPPerformance {
  PPPerformance._();

  static final FirebasePerformance _perf = FirebasePerformance.instance;

  // ── Trace names (matches iOS enum values / string literals) ───────────────

  static const String tracePropertyListLoad  = 'property_list_load';
  static const String tracePropertyDetail    = 'property_detail_load';
  static const String traceImageUpload       = 'image_upload';
  static const String traceSearch            = 'search_query';
  static const String traceMessageSend       = 'message_send';
  static const String traceSignIn            = 'sign_in';
  static const String traceBooking           = 'booking_flow';
  static const String traceMapLoad           = 'map_load';

  // ── Trace API ─────────────────────────────────────────────────────────────

  /// Mirrors iOS: `AppPerformanceTracing.startTrace(named:)`
  /// Returns null in debug mode so callers don't need to guard.
  static Future<Trace?> startTrace(String name) async {
    if (kDebugMode) return null;
    try {
      final trace = _perf.newTrace(name);
      await trace.start();
      return trace;
    } catch (_) {
      return null;
    }
  }

  /// Mirrors iOS: `AppPerformanceTracing.stopTrace(_ trace:)`
  static Future<void> stopTrace(Trace? trace) async {
    try {
      await trace?.stop();
    } catch (_) {}
  }

  /// Set a custom metric on an active trace.
  /// iOS: trace.setValue(value, forMetric: key)
  static void setMetric(Trace? trace, String key, int value) {
    try {
      trace?.setMetric(key, value);
    } catch (_) {}
  }

  /// Set a custom attribute on an active trace.
  /// iOS: trace.setAttribute(value, forName: key)
  static void setAttribute(Trace? trace, String key, String value) {
    try {
      trace?.putAttribute(key, value);
    } catch (_) {}
  }

  // ── HTTP Metrics (mirrors iOS URLSession + Firebase Performance auto-monitoring) ──

  /// Wrap an HTTP operation with Firebase Performance HTTP metrics.
  /// iOS: automatically instrumented via URLSession swizzling.
  /// Android: must be done manually for non-http package clients.
  static Future<T> measureHttpCall<T>({
    required String url,
    required String method,
    required Future<T> Function() call,
  }) async {
    if (kDebugMode) return call();
    HttpMetric? metric;
    try {
      metric = _perf.newHttpMetric(url, _httpMethod(method));
      await metric.start();
    } catch (_) {}
    try {
      final result = await call();
      await metric?.stop();
      return result;
    } catch (e) {
      try {
        metric?.httpResponseCode = 0;
        await metric?.stop();
      } catch (_) {}
      rethrow;
    }
  }

  static HttpMethod _httpMethod(String method) {
    switch (method.toUpperCase()) {
      case 'GET':    return HttpMethod.Get;
      case 'POST':   return HttpMethod.Post;
      case 'PUT':    return HttpMethod.Put;
      case 'DELETE': return HttpMethod.Delete;
      case 'PATCH':  return HttpMethod.Patch;
      default:       return HttpMethod.Get;
    }
  }

  // ── Convenience wrappers ──────────────────────────────────────────────────

  /// Time a synchronous or async operation with a named trace.
  static Future<T> measure<T>(String traceName, Future<T> Function() work) async {
    final trace = await startTrace(traceName);
    try {
      final result = await work();
      await stopTrace(trace);
      return result;
    } catch (e) {
      await stopTrace(trace);
      rethrow;
    }
  }
}
