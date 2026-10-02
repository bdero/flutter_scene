/// Acquiring a WebGPU device, and the facts backend selection needs about it.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'webgpu_interop.dart';

/// Why [WebGpuDevice.request] returned no device.
enum WebGpuUnavailableReason {
  /// `navigator.gpu` is absent (browser, flag, or insecure context).
  noApi,

  /// `requestAdapter` resolved to null.
  noAdapter,

  /// Only a software adapter exists and the caller did not accept one.
  fallbackAdapterRejected,

  /// `requestDevice` rejected.
  deviceRequestFailed,
}

/// The outcome of a [WebGpuDevice.request], usable or not.
final class WebGpuProbe {
  const WebGpuProbe._({
    this.device,
    this.reason,
    this.detail = '',
    this.adapterSummary = '',
    this.isFallbackAdapter = false,
  });

  final WebGpuDevice? device;
  final WebGpuUnavailableReason? reason;

  /// Error text from a failed request, for the selection log line.
  final String detail;

  /// Vendor, architecture, and description, as the adapter reports them.
  final String adapterSummary;

  /// Whether the adapter is a software implementation (SwiftShader).
  final bool isFallbackAdapter;

  bool get available => device != null;

  @override
  String toString() => available
      ? 'WebGPU available ($adapterSummary'
            '${isFallbackAdapter ? ', fallback adapter' : ''})'
      : 'WebGPU unavailable: ${reason!.name}'
            '${detail.isEmpty ? '' : ' ($detail)'}'
            '${adapterSummary.isEmpty ? '' : ' [$adapterSummary]'}';
}

/// A WebGPU device and the adapter facts the shim reads from it.
final class WebGpuDevice {
  WebGpuDevice._(this.gpu, this.adapter, this.device);

  final GPU gpu;
  final GPUAdapter adapter;
  final GPUDevice device;

  /// The swapchain format the browser prefers (`bgra8unorm` or `rgba8unorm`).
  String get preferredCanvasFormat => gpu.getPreferredCanvasFormat();

  /// Requests an adapter and a device.
  ///
  /// A software adapter is rejected unless [allowFallbackAdapter], since
  /// WebGL2 through ANGLE may still be hardware on the same machine.
  static Future<WebGpuProbe> request({
    bool allowFallbackAdapter = false,
  }) async {
    final api = web.window.navigator.gpuOrNull;
    if (api == null || !api.isA<JSObject>()) {
      return const WebGpuProbe._(reason: WebGpuUnavailableReason.noApi);
    }
    final gpu = api as GPU;

    final GPUAdapter? adapter;
    try {
      adapter = await gpu
          .requestAdapter(
            GPURequestAdapterOptions(powerPreference: 'high-performance'),
          )
          .toDart;
    } catch (e) {
      return WebGpuProbe._(
        reason: WebGpuUnavailableReason.noAdapter,
        detail: '$e',
      );
    }
    if (adapter == null) {
      return const WebGpuProbe._(reason: WebGpuUnavailableReason.noAdapter);
    }

    final summary = _adapterSummary(adapter);
    final fallback = _isFallback(adapter);
    if (fallback && !allowFallbackAdapter) {
      return WebGpuProbe._(
        reason: WebGpuUnavailableReason.fallbackAdapterRejected,
        adapterSummary: summary,
        isFallbackAdapter: true,
      );
    }

    try {
      final device = await adapter.requestDevice().toDart;
      return WebGpuProbe._(
        device: WebGpuDevice._(gpu, adapter, device),
        adapterSummary: summary,
        isFallbackAdapter: fallback,
      );
    } catch (e) {
      return WebGpuProbe._(
        reason: WebGpuUnavailableReason.deviceRequestFailed,
        detail: '$e',
        adapterSummary: summary,
        isFallbackAdapter: fallback,
      );
    }
  }

  static String _adapterSummary(GPUAdapter adapter) {
    final info = adapter.info;
    return [
      info.vendor,
      info.architecture,
      info.description,
    ].where((s) => s.isNotEmpty).join(' / ');
  }

  static bool _isFallback(GPUAdapter adapter) {
    final fromInfo = adapter.info.isFallbackAdapter;
    if (fromInfo != null) return fromInfo;
    // Older Chrome exposes the flag on the adapter only.
    final legacy = adapter.getProperty<JSAny?>('isFallbackAdapter'.toJS);
    return legacy != null &&
        legacy.isA<JSBoolean>() &&
        (legacy as JSBoolean).toDart;
  }
}
