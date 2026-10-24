# volume_bench

GPU benchmark for data textures (dev-only, not published). It generates a synthetic 16-bit density field (Gaussian blobs over a cosine lattice), stores it several ways, and times two workloads over a fixed 1024 x 1024 target:

- **Reslice**: an oblique plane through the volume, one trilinear sample per pixel.
- **MIP**: a maximum intensity projection, ray-marched at one voxel per step.

Draws go straight through the GPU shim (a fullscreen triangle into an offscreen texture), so only the fetch path differs between variants. Each variant's image is read back and compared with the atlas's.

| Storage | Bytes/voxel | Material does |
| --- | --- | --- |
| RGBA8 atlas (the workaround) | 2 (two 16-bit voxels per texel) | 8 `texelFetch`, manual trilinear |
| 2D array r8 / rg8 / r32f | 1 / 2 / 4 | 2 bilinear fetches, blended across layers |
| 3D r8 / rg8 / r32f (web only) | 1 / 2 / 4 | 1 trilinear fetch |

rg8 stores 16-bit values high byte in red; filtering is linear, so `r * 65280 + g * 255` of a filtered texel is the filtered value.

## Running

```sh
# macOS (Metal)
flutter build macos --profile
build/macos/Build/Products/Profile/volume_bench.app/Contents/MacOS/volume_bench

# Chrome (WebGL2); serve build/web from its root and open it
flutter build web --release

# Another size
flutter build macos --profile --dart-define=volume_bench.size=512x512x400
```

The app prints one row per variant, a Markdown table, and a `BENCH_JSON` line, and shows each variant's images.

## Timing

- **WebGL2**: `EXT_disjoint_timer_query_webgl2` where the browser exposes it (Chrome does), which is GPU time only. Otherwise a blocking `finish`.
- **Flutter GPU**: no timer queries, so wall time from the first submission to the last command buffer's completion callback, over enough passes for about 50 ms of work. On Metal that callback fires when the GPU retires the buffer. The table header gives the cost of an empty pass timed the same way. Reslice draws 16 times per pass (additively blended, so a tile-based GPU cannot cull the earlier draws) to rise above that floor.
- **Upload**: creating the textures and writing every texel, until an empty command buffer submitted after the writes completes.
- **Memory**: texel bytes allocated, excluding driver padding.

## Results

Apple M1 Pro, macOS 27.0.1, Flutter 3.50.0-0.2.pre (beta), Chrome 156 (WebGL2 on ANGLE). Median ms per full-screen draw over 7 samples. "Diff" is the max / mean gray-level difference from the atlas image, out of 255. An empty pass measured 0.058 ms on Metal (completion timing) and 0.002 ms on WebGL2 (GPU timer).

### 256 x 256 x 256

| Backend | Storage | MiB | Upload ms | Reslice ms | MIP ms | Diff (reslice, MIP) |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Metal | RGBA8 atlas | 32 | 8 | 0.163 | 33.4 | reference |
| Metal | 2D array r8 | 16 | 14 | 0.024 | 2.85 | 1/0.27, 1/0.21 |
| Metal | 2D array rg8 | 32 | 17 | 0.027 | 3.68 | 1/0.01, 1/0.01 |
| Metal | 2D array r32f | 64 | 64 | 0.027 | 6.81 | 1/0.00, 1/0.00 |
| WebGL2 | RGBA8 atlas | 32 | 21 | 0.157 | 10.6 | reference |
| WebGL2 | 2D array r8 | 16 | 32 | 0.026 | 3.33 | 1/0.27, 1/0.21 |
| WebGL2 | 2D array rg8 | 32 | 15 | 0.030 | 3.51 | 1/0.01, 1/0.01 |
| WebGL2 | 2D array r32f | 64 | 51 | 0.026 | 4.10 | 1/0.00, 1/0.00 |
| WebGL2 | 3D r8 | 16 | 12 | 0.018 | 2.26 | 1/0.26, 1/0.20 |
| WebGL2 | 3D rg8 | 32 | 17 | 0.020 | 2.23 | 1/0.01, 1/0.01 |
| WebGL2 | 3D r32f | 64 | 25 | 0.017 | 3.17 | 1/0.00, 1/0.00 |

### 512 x 512 x 400

| Backend | Storage | MiB | Upload ms | Reslice ms | MIP ms |
| --- | --- | ---: | ---: | ---: | ---: |
| Metal | RGBA8 atlas (4 pages) | 200 | 74 | 0.154 | 87.8 |
| Metal | 2D array r8 | 100 | 38 | 0.022 | 11.6 |
| Metal | 2D array rg8 | 200 | 57 | 0.024 | 51.4 |
| Metal | 2D array r32f | 400 | 137 | 0.023 | 121.2 |
| WebGL2 | RGBA8 atlas (4 pages) | 200 | 114 | 0.174 | 35.6 |
| WebGL2 | 2D array r8 | 100 | 69 | 0.024 | 12.7 |
| WebGL2 | 2D array rg8 | 200 | 188 | 0.027 | 39.0 |
| WebGL2 | 2D array r32f | 400 | 327 | 0.024 | 77.7 |
| WebGL2 | 3D r8 | 100 | 117 | 0.015 | 13.1 |
| WebGL2 | 3D rg8 | 200 | 134 | 0.019 | 32.3 |
| WebGL2 | 3D r32f | 400 | 390 | 0.018 | 61.1 |

Image differences at 512 x 512 x 400 match the 256³ run (at most 1 gray level).

### Reading them

- Hardware filtering takes the reslice from 8 fetches to 2 (array) or 1 (3D): 6x faster on Metal, 5 to 9x on WebGL2, at the same 16-bit precision and memory.
- At 256³ the MIP is 9x faster on Metal with a 2D array (rg8) than with the atlas, and 3x on WebGL2; a 3D texture saves another third on WebGL2.
- At 512 x 512 x 400 the MIP is bound by memory bandwidth, so bytes per voxel decide the time. rg8 is 1.7x faster than the atlas on Metal and about level on WebGL2, while r8 (half the bytes, 8-bit precision) is 3 to 8x faster and r32f the slowest.
- The atlas MIP costs 33 ms on Metal through Flutter GPU but 10.6 ms on WebGL2 (ANGLE on the same GPU) from the same GLSL source, while the array variants cost about the same on both. The atlas shader's integer division, modulo, and four-way sampler branch are the likely difference in the generated Metal; not investigated further.
