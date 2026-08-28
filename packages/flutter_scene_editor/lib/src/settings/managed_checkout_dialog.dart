/// Progress dialog for a running managed-checkout creation, the six named
/// phases with a live log tail, Cancel while running, and Close when done.
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart' hide FTheme;

import '../toolchains/managed_checkout.dart';
import '../shell/editor_theme.dart';
import '../shell/editor_dialog.dart';

/// Shows [job]'s progress. Resolves when the dialog closes; the job's result
/// (or error) is on the job itself.
Future<void> showManagedCheckoutDialog(
  BuildContext context,
  ManagedCheckoutJob job,
) {
  return showEditorDialog<void>(
    context,
    barrierDismissible: false,
    builder: (context) => Dialog(child: _ManagedCheckoutProgress(job: job)),
  );
}

class _ManagedCheckoutProgress extends StatelessWidget {
  const _ManagedCheckoutProgress({required this.job});

  final ManagedCheckoutJob job;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 560,
      height: 420,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: job,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Creating managed Flutter checkout',
                  style: editorDialogTitleText,
                ),
                const SizedBox(height: 10),
                for (final phase in ManagedCheckoutPhase.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 14,
                          child: _phaseIcon(context, phase),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          phase.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: phase.index > job.phase.index
                                ? editorMutedTextColor
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Expanded(child: _logView(context)),
                if (job.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      job.error!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: editorErrorColor,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FButton(
                    variant: .outline,
                    size: .xs,
                    mainAxisSize: .min,
                    onPress: job.done
                        ? () => Navigator.of(context).pop()
                        : job.cancel,
                    child: Text(job.done ? 'Close' : 'Cancel'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _phaseIcon(BuildContext context, ManagedCheckoutPhase phase) {
    if (phase.index < job.phase.index ||
        (job.done && job.error == null && phase.index <= job.phase.index)) {
      return const Icon(Icons.check, size: 14, color: editorSuccessColor);
    }
    if (phase == job.phase) {
      if (job.done) {
        return Icon(
          job.error == null ? Icons.check : Icons.close,
          size: 14,
          color: job.error == null ? editorSuccessColor : editorErrorColor,
        );
      }
      return const SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _logView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: editorPanelBox(color: editorSurfaceColor),
      child: SingleChildScrollView(
        reverse: true,
        child: SelectableText(
          job.log.join('\n'),
          style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
