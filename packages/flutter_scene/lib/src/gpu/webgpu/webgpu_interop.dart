/// Hand-written js_interop bindings for the slice of the WebGPU API the shim
/// uses. `package:web` ships none beyond the usage constants.
///
/// Spec: https://www.w3.org/TR/webgpu/ (interfaces and dictionaries below keep
/// the spec's names, so each one can be checked against it directly).
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// `navigator.gpu`, absent where WebGPU is not exposed.
extension NavigatorGpu on web.Navigator {
  @JS('gpu')
  external JSAny? get gpuOrNull;
}

extension type GPU._(JSObject _) implements JSObject {
  external JSPromise<GPUAdapter?> requestAdapter([
    GPURequestAdapterOptions? options,
  ]);
  external String getPreferredCanvasFormat();
}

extension type GPURequestAdapterOptions._(JSObject _) implements JSObject {
  external factory GPURequestAdapterOptions({String powerPreference});
}

extension type GPUAdapter._(JSObject _) implements JSObject {
  external GPUSupportedFeatures get features;
  external GPUSupportedLimits get limits;
  external GPUAdapterInfo get info;
  external JSPromise<GPUDevice> requestDevice([
    GPUDeviceDescriptor? descriptor,
  ]);
}

extension type GPUAdapterInfo._(JSObject _) implements JSObject {
  external String get vendor;
  external String get architecture;
  external String get device;
  external String get description;

  /// Newer location of the fallback flag; older Chrome only had it on the
  /// adapter itself.
  external bool? get isFallbackAdapter;
}

/// A setlike of feature names.
extension type GPUSupportedFeatures._(JSObject _) implements JSObject {
  external bool has(String feature);
}

extension type GPUSupportedLimits._(JSObject _) implements JSObject {
  external int get maxTextureDimension2D;
  external int get maxBindGroups;
  external int get maxSampledTexturesPerShaderStage;
  external int get maxSamplersPerShaderStage;
  external int get maxUniformBufferBindingSize;
  external int get minUniformBufferOffsetAlignment;
}

extension type GPUDeviceDescriptor._(JSObject _) implements JSObject {
  external factory GPUDeviceDescriptor({JSArray<JSString> requiredFeatures});
}

extension type GPUDevice._(JSObject _) implements JSObject {
  external GPUQueue get queue;
  external GPUSupportedFeatures get features;
  external GPUSupportedLimits get limits;
  external JSPromise<GPUDeviceLostInfo> get lost;
  external GPUCommandEncoder createCommandEncoder();
  external GPUBuffer createBuffer(GPUBufferDescriptor descriptor);
  external GPUTexture createTexture(JSObject descriptor);
  external GPUSampler createSampler(JSObject descriptor);
  external GPUShaderModule createShaderModule(JSObject descriptor);
  external GPURenderPipeline createRenderPipeline(JSObject descriptor);
  external GPUBindGroup createBindGroup(JSObject descriptor);
  external void pushErrorScope(String filter);
  external JSPromise<GPUError?> popErrorScope();
  external void destroy();
}

extension type GPUError._(JSObject _) implements JSObject {
  external String get message;
}

/// `GPUBufferUsage` flags.
abstract final class GPUBufferUsage {
  static const int mapRead = 0x0001;
  static const int copySrc = 0x0004;
  static const int copyDst = 0x0008;
  static const int index = 0x0010;
  static const int vertex = 0x0020;
  static const int uniform = 0x0040;
  static const int storage = 0x0080;
}

/// `GPUTextureUsage` flags.
abstract final class GPUTextureUsage {
  static const int copySrc = 0x01;
  static const int copyDst = 0x02;
  static const int textureBinding = 0x04;
  static const int storageBinding = 0x08;
  static const int renderAttachment = 0x10;
}

extension type GPUBufferDescriptor._(JSObject _) implements JSObject {
  external factory GPUBufferDescriptor({
    int size,
    int usage,
    bool mappedAtCreation,
  });
}

extension type GPUBuffer._(JSObject _) implements JSObject {
  external int get size;
  external JSPromise<JSAny?> mapAsync(int mode);
  external JSArrayBuffer getMappedRange();
  external void unmap();
  external void destroy();
}

extension type GPUSampler._(JSObject _) implements JSObject {}

extension type GPUShaderModule._(JSObject _) implements JSObject {}

extension type GPURenderPipeline._(JSObject _) implements JSObject {
  external JSObject getBindGroupLayout(int index);
}

extension type GPUBindGroup._(JSObject _) implements JSObject {}

extension type GPUDeviceLostInfo._(JSObject _) implements JSObject {
  external String get reason;
  external String get message;
}

extension type GPUQueue._(JSObject _) implements JSObject {
  external void submit(JSArray<GPUCommandBuffer> commandBuffers);
  external void writeBuffer(
    GPUBuffer buffer,
    int bufferOffset,
    JSObject data, [
    int dataOffset,
    int size,
  ]);
  external void writeTexture(
    JSObject destination,
    JSObject data,
    JSObject dataLayout,
    JSObject size,
  );
  external void copyExternalImageToTexture(
    JSObject source,
    JSObject destination,
    JSObject copySize,
  );
  external JSPromise<JSAny?> onSubmittedWorkDone();
}

extension type GPUCommandBuffer._(JSObject _) implements JSObject {}

extension type GPUCommandEncoder._(JSObject _) implements JSObject {
  external GPURenderPassEncoder beginRenderPass(JSObject descriptor);
  external void copyTextureToBuffer(
    JSObject source,
    JSObject destination,
    JSObject copySize,
  );
  external void copyBufferToBuffer(
    GPUBuffer source,
    int sourceOffset,
    GPUBuffer destination,
    int destinationOffset,
    int size,
  );
  external GPUCommandBuffer finish();
}

extension type GPURenderPassEncoder._(JSObject _) implements JSObject {
  external void setPipeline(GPURenderPipeline pipeline);
  external void setBindGroup(int index, GPUBindGroup bindGroup);
  external void draw(int vertexCount);
  external void end();
}

extension type GPURenderPassDescriptor._(JSObject _) implements JSObject {
  external factory GPURenderPassDescriptor({
    JSArray<GPURenderPassColorAttachment> colorAttachments,
  });
}

extension type GPURenderPassColorAttachment._(JSObject _) implements JSObject {
  external factory GPURenderPassColorAttachment({
    GPUTextureView view,
    GPUColorDict clearValue,
    String loadOp,
    String storeOp,
  });
}

extension type GPUColorDict._(JSObject _) implements JSObject {
  external factory GPUColorDict({double r, double g, double b, double a});
}

extension type GPUTexture._(JSObject _) implements JSObject {
  external GPUTextureView createView([JSObject? descriptor]);
  external void destroy();
  external int get width;
  external int get height;
  external String get format;
}

extension type GPUTextureView._(JSObject _) implements JSObject {}

extension type GPUCanvasContext._(JSObject _) implements JSObject {
  external void configure(GPUCanvasConfiguration configuration);
  external void unconfigure();
  external GPUTexture getCurrentTexture();
}

extension type GPUCanvasConfiguration._(JSObject _) implements JSObject {
  external factory GPUCanvasConfiguration({
    GPUDevice device,
    String format,
    String alphaMode,
  });
}
