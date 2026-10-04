#!/usr/bin/env python3
"""Compares two directories of smoke frames scene by scene.

    compare_frames.py <reference_dir> <candidate_dir> [--diff-dir DIR]
        [--max-mean 1.0] [--max-outliers 0.5]

A scene passes when its mean absolute channel difference is at most
--max-mean (0-255 scale) and at most --max-outliers percent of its pixels
differ by more than 16 in any channel. Exits nonzero when a scene fails or
is missing from either side. Needs Pillow and NumPy.
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('reference')
    parser.add_argument('candidate')
    parser.add_argument('--diff-dir')
    parser.add_argument('--max-mean', type=float, default=1.0)
    parser.add_argument('--max-outliers', type=float, default=0.5)
    args = parser.parse_args()

    def frames(path):
        return {f for f in os.listdir(path) if f.endswith('.png')}

    names = sorted(frames(args.reference) | frames(args.candidate))
    failures = []
    for name in names:
        a = os.path.join(args.reference, name)
        b = os.path.join(args.candidate, name)
        if not (os.path.exists(a) and os.path.exists(b)):
            side = 'reference' if not os.path.exists(a) else 'candidate'
            print(f'{name}: MISSING from {side}')
            failures.append(name)
            continue
        ia = np.asarray(Image.open(a).convert('RGBA'), dtype=np.int16)
        ib = np.asarray(Image.open(b).convert('RGBA'), dtype=np.int16)
        if ia.shape != ib.shape:
            print(f'{name}: SIZE {ia.shape} vs {ib.shape}')
            failures.append(name)
            continue
        diff = np.abs(ia - ib)
        per_pixel = diff.max(axis=2)
        mean = float(diff.mean())
        outliers = 100.0 * float((per_pixel > 16).mean())
        ok = mean <= args.max_mean and outliers <= args.max_outliers
        print(f'{"ok  " if ok else "FAIL"} {name}: max {int(diff.max())}, '
              f'mean {mean:.3f}, {outliers:.3f}% of pixels past 16')
        if not ok:
            failures.append(name)
        if args.diff_dir and diff.max() > 0:
            os.makedirs(args.diff_dir, exist_ok=True)
            scaled = np.clip(per_pixel * 8, 0, 255).astype(np.uint8)
            Image.fromarray(scaled, 'L').save(os.path.join(args.diff_dir, name))
    print(f'{len(names)} scenes, {len(failures)} failed'
          + (f': {", ".join(failures)}' if failures else ''))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
