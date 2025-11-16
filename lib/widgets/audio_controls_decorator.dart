import 'package:flutter/cupertino.dart';
import '../services/waveform_controller.dart';
import '../widgets/native_waveform.dart';
import '../theme/dictation_styles.dart';

/// A decorator widget that adds audio recording controls (mic/checkmark, timer, cancel, waveform)
/// below a provided child widget (typically a text field).
class AudioControlsDecorator extends StatelessWidget {
  final Widget child;
  final bool isListening;
  final bool isProcessing; // New state for processing
  final Duration elapsedTime;
  final WaveformController? waveformController; // Optional for native waveform
  final VoidCallback? onMicPressed; // Toggles listening state (mic/checkmark)
  final VoidCallback? onCancelPressed; // Callback for cancel button

  const AudioControlsDecorator({
    super.key,
    required this.child,
    required this.isListening,
    this.isProcessing = false, // Default to false
    required this.elapsedTime,
    this.waveformController,
    this.onMicPressed,
    this.onCancelPressed,
  });

  // Helper to format duration M:SS
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min, // Take minimum vertical space
      crossAxisAlignment:
          CrossAxisAlignment.stretch, // Stretch control row width
      children: [
        child, // Display the decorated widget (e.g., TextField)
        const SizedBox(
          height: 8.0,
        ), // Add spacing between text field and controls
        // Build the control row below the child widget
        _buildControlRow(context),
      ],
    );
  }

  // Helper to build the control row based on listening state
  Widget _buildControlRow(BuildContext context) {
    // If not listening, show only Mic button (aligned right)
    if (!isListening) {
      if (onMicPressed == null) {
        return const SizedBox.shrink(); // No controls if no action
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8.0), // Add some spacing
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DictationStyles.secondaryTextColor(context).withValues(alpha: 0.1),
            ),
            child: CupertinoButton(
              padding: const EdgeInsets.all(12.0),
              minSize: 60, // Larger tap area
              onPressed: onMicPressed,
              child: Icon(
                CupertinoIcons.mic,
                color: DictationStyles.secondaryTextColor(context),
                size: 32.0, // Larger icon size
              ),
            ),
          ),
        ],
      );
    }

    // If listening, show the full control row
    const double controlRowHeight = 40.0;
    const double waveformHeight = 30.0;
    
    // Use the same color for buttons and waveform to ensure they match
    final buttonColor = DictationStyles.secondaryTextColor(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: controlRowHeight,
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Cancel Button (Left)
              if (onCancelPressed != null)
                CupertinoButton(
                  padding: const EdgeInsets.only(right: 8.0),
                  minSize: 30,
                  onPressed: onCancelPressed,
                  child: Icon(
                    CupertinoIcons.xmark_circle_fill,
                    color: buttonColor,
                    size: 20.0,
                  ),
                ),

              // Waveform (Middle, Expanded)
              if (waveformController != null)
                Expanded(
                  child: NativeWaveform(
                    controller: waveformController!,
                    height: waveformHeight,
                    color: buttonColor,
                  ),
                ),
              if (waveformController == null) const Spacer(),
              // Timer and Checkmark/Processing (Right)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Timer Text
                  Text(
                    _formatDuration(elapsedTime),
                    style: DictationStyles.inputTextStyle(context).copyWith(
                      color: buttonColor,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  // Checkmark/Processing Button
                  if (isProcessing)
                    const SizedBox(
                      width: 20.0,
                      height: 20.0,
                      child: CupertinoActivityIndicator(radius: 10.0),
                    )
                  else
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 30,
                      onPressed: onMicPressed,
                      child: Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        color: buttonColor,
                        size: 20.0,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

