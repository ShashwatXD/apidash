import 'dart:io';
import 'package:apidash/consts.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';

class VideoPreviewer extends StatefulWidget {
  const VideoPreviewer({
    super.key,
    required this.videoBytes,
  });

  final Uint8List videoBytes;

  @override
  State<VideoPreviewer> createState() => _VideoPreviewerState();
}

class _VideoPreviewerState extends State<VideoPreviewer> {
  VideoPlayerController? _videoController;
  Future<void>? _initializeVideoPlayerFuture;
  bool _isPlaying = false;
  File? _tempVideoFile;
  bool _showControls = false;
  bool _isInitialized = false;
  double _savedVolume = 1.0; // Track volume for restoration
  bool _userWantsPaused = false; // Track if user explicitly paused
  
  // Debug tracking - only log significant changes
  bool _lastKnownPlayingState = false;
  double _lastKnownVolume = 1.0;
  Duration _lastKnownPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    registerWithAllPlatforms();
    _initializeVideoPlayerFuture = _initializeVideoPlayer();
  }

  void registerWithAllPlatforms() {
    try {
      debugPrint("📦 fvp.registerWith() called on ${Platform.operatingSystem}");
      fvp.registerWith();
      debugPrint("   ✓ fvp registration successful\n");
    } catch (e, stackTrace) {
      debugPrint("❌ fvp.registerWith() ERROR: $e");
      debugPrint("   Stack: $stackTrace");
    }
  }

  Future<void> _initializeVideoPlayer() async {
    final tempDir = await getTemporaryDirectory();
    _tempVideoFile = File(
        '${tempDir.path}/temp_video_${DateTime.now().millisecondsSinceEpoch}');
    try {
      await _tempVideoFile!.writeAsBytes(widget.videoBytes);
      _videoController = VideoPlayerController.file(_tempVideoFile!);
      await _videoController!.initialize();
      
      // Add listener to sync state with actual player state
      _videoController!.addListener(_videoPlayerListener);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          // CRITICAL: Don't enable looping initially - it causes auto-restart issues on macOS
          // We'll enable it only when user explicitly plays
          _videoController!.setLooping(false);
          _videoController!.play();
          _isPlaying = true;
        });
      }
    } catch (e) {
      debugPrint("VideoPreviewer _initializeVideoPlayer(): $e");
      // Clean up on error
      await _cleanup();
      return;
    }
  }

  void _videoPlayerListener() {
    if (!mounted || _videoController == null) return;
    
    final value = _videoController!.value;
    
    // CRITICAL FIX: If user wants paused but video restarted (auto-loop), force pause again
    if (_userWantsPaused && value.isPlaying) {
      debugPrint("🚫 AUTO-RESTART DETECTED! User wants paused but video restarted. Forcing pause...");
      _videoController!.pause();
      _videoController!.setVolume(0.0);
      return; // Exit early, we'll handle state update next time
    }
    
    // CRITICAL FIX: Keep volume muted if user wants paused (even if video reaches end)
    if (_userWantsPaused && value.volume > 0.01) {
      debugPrint("🚫 Volume restored while paused! Re-muting...");
      _videoController!.setVolume(0.0);
    }
    
    // Only log SIGNIFICANT state changes, not every frame update
    bool shouldLog = false;
    String logReason = "";
    
    // Check for play/pause state change
    if (value.isPlaying != _lastKnownPlayingState) {
      shouldLog = true;
      logReason = "PLAY/PAUSE STATE CHANGE";
      _lastKnownPlayingState = value.isPlaying;
    }
    
    // Check for volume change
    if ((value.volume - _lastKnownVolume).abs() > 0.01) {
      shouldLog = true;
      logReason = "VOLUME CHANGE";
      _lastKnownVolume = value.volume;
    }
    
    // Check for significant position jump (seeking)
    if ((value.position - _lastKnownPosition).inSeconds.abs() > 2) {
      shouldLog = true;
      logReason = "SEEK/POSITION JUMP";
      _lastKnownPosition = value.position;
    }
    
    // Log only significant changes
    if (shouldLog) {
      debugPrint("🎬 VIDEO PLAYER STATE CHANGE: $logReason");
      debugPrint("   isPlaying: ${value.isPlaying} | volume: ${value.volume} | position: ${value.position.inSeconds}s");
    }
    
    // Sync UI state with actual player state
    final isActuallyPlaying = value.isPlaying;
    if (_isPlaying != isActuallyPlaying) {
      if (!shouldLog) {
        debugPrint("🎬 PLAY/PAUSE UI SYNC: $_isPlaying → $isActuallyPlaying");
      }
      setState(() {
        _isPlaying = isActuallyPlaying;
      });
    }
    
    // Update last known position (but don't log it)
    _lastKnownPosition = value.position;
  }

  Future<void> _stopVideoAndAudio() async {
    if (_videoController == null || !_isInitialized) return;
    
    debugPrint("🛑 === STOPPING VIDEO/AUDIO ===");
    final beforeState = _videoController!.value;
    debugPrint("   Before: isPlaying=${beforeState.isPlaying}, volume=${beforeState.volume}, pos=${beforeState.position.inSeconds}s");
    
    try {
      // CRITICAL FIX for macOS: On macOS with fvp, pause() doesn't stop audio stream
      // The key issue: looping causes seek to restart playback!
      
      // Step 1: Disable looping FIRST - prevents seek from restarting
      await _videoController!.setLooping(false);
      debugPrint("   ✓ Step 1: Disabled looping");
      
      // Step 2: Pause the video
      await _videoController!.pause();
      await Future.delayed(const Duration(milliseconds: 100));
      debugPrint("   ✓ Step 2: Paused - isPlaying=${_videoController!.value.isPlaying}");
      
      // Step 3: Set volume to 0 to mute audio
      await _videoController!.setVolume(0.0);
      debugPrint("   ✓ Step 3: Volume set to 0 - volume=${_videoController!.value.volume}");
      
      // Step 4: Seek to beginning (not end) - stops audio buffer without triggering loop
      await _videoController!.seekTo(Duration.zero);
      debugPrint("   ✓ Step 4: Seeked to start - pos=${_videoController!.value.position.inSeconds}s");
      
      // Step 5: Additional pause to ensure everything stops
      await Future.delayed(const Duration(milliseconds: 50));
      await _videoController!.pause();
      final afterState = _videoController!.value;
      debugPrint("   ✓ Step 5: Final pause - isPlaying=${afterState.isPlaying}");
      debugPrint("   After: isPlaying=${afterState.isPlaying}, volume=${afterState.volume}, pos=${afterState.position.inSeconds}s");
      debugPrint("🛑 === STOP COMPLETED ===\n");
      
    } catch (e, stackTrace) {
      debugPrint("❌ ERROR in _stopVideoAndAudio(): $e");
      debugPrint("   Stack: $stackTrace");
    }
  }

  Future<void> _cleanup() async {
    if (_videoController != null) {
      try {
        // Remove listener before disposal
        _videoController!.removeListener(_videoPlayerListener);
        // Stop video and audio
        await _stopVideoAndAudio();
        // Dispose the controller
        await _videoController!.dispose();
      } catch (e) {
        debugPrint("VideoPreviewer _cleanup() dispose error: $e");
      }
      _videoController = null;
    }
    
    // Clean up temp file
    if (_tempVideoFile != null && !kIsRunningTests) {
      try {
        // Wait a bit for file handles to be released
        await Future.delayed(const Duration(milliseconds: 500));
        if (await _tempVideoFile!.exists()) {
          await _tempVideoFile!.delete();
        }
      } catch (e) {
        debugPrint("VideoPreviewer _cleanup() file delete error: $e");
      }
      _tempVideoFile = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).iconTheme.color;
    final progressBarColors = VideoProgressColors(
      playedColor: iconColor!,
      bufferedColor: iconColor.withValues(alpha: 0.5),
      backgroundColor: iconColor.withValues(alpha: 0.3),
    );
    return Scaffold(
      body: FutureBuilder(
        future: _initializeVideoPlayerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (_isInitialized && 
                _videoController != null && 
                _videoController!.value.isInitialized) {
              return MouseRegion(
                onEnter: (_) => setState(() => _showControls = true),
                onExit: (_) => setState(() => _showControls = false),
                child: Stack(
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SizedBox(
                        height: 50.0,
                        child: VideoProgressIndicator(
                          _videoController!,
                          allowScrubbing: true,
                          padding: const EdgeInsets.all(20),
                          colors: progressBarColors,
                        ),
                      ),
                    ),
                    if (_showControls)
                      Center(
                        child: GestureDetector(
                          onTap: () async {
                            if (_videoController == null || !_isInitialized) return;
                            
                            if (_videoController!.value.isPlaying) {
                              debugPrint("⏸️  USER TAPPED PAUSE");
                              // Set flag that user wants paused - listener will enforce this
                              _userWantsPaused = true;
                              
                              // Save current volume before muting
                              _savedVolume = _videoController!.value.volume;
                              
                              // STEP 1: Mute audio FIRST - this stops audio immediately
                              await _videoController!.setVolume(0.0);
                              debugPrint("   ✓ Step 1: Muted audio (volume=0)");
                              
                              // STEP 2: Disable looping to prevent auto-restart
                              await _videoController!.setLooping(false);
                              debugPrint("   ✓ Step 2: Disabled looping");
                              
                              // STEP 3: Pause the video
                              await _videoController!.pause();
                              debugPrint("   ✓ Step 3: Paused video");
                              
                              // STEP 4: Wait and verify pause took effect
                              await Future.delayed(const Duration(milliseconds: 200));
                              
                              // STEP 5: Force pause again (in case it restarted)
                              if (_videoController!.value.isPlaying) {
                                debugPrint("   ⚠️  Video still playing, forcing pause...");
                                await _videoController!.pause();
                                await _videoController!.setVolume(0.0);
                              }
                              
                              debugPrint("   Final state: isPlaying=${_videoController!.value.isPlaying}, volume=${_videoController!.value.volume}");
                              debugPrint("⏸️  PAUSE OPERATIONS COMPLETE\n");
                            } else {
                              debugPrint("▶️  USER TAPPED PLAY");
                              // Clear pause flag - user wants to play
                              _userWantsPaused = false;
                              
                              // Restore volume first
                              await _videoController!.setVolume(_savedVolume);
                              debugPrint("   ✓ Restored volume to $_savedVolume");
                              // Enable looping BEFORE playing (prevents restart issues)
                              await _videoController!.setLooping(true);
                              debugPrint("   ✓ Enabled looping");
                              await Future.delayed(const Duration(milliseconds: 50));
                              await _videoController!.play();
                              debugPrint("▶️  PLAY OPERATIONS COMPLETE\n");
                            }
                            // State will be updated via listener
                          },
                          child: Container(
                            color: Colors.transparent,
                            child: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 64,
                              color: iconColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading video: ${snapshot.error}',
                style: TextStyle(color: iconColor),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  @override
  void dispose() {
    debugPrint("🗑️  === DISPOSING VideoPreviewer ===");
    if (_videoController != null) {
      final state = _videoController!.value;
      debugPrint("   Before dispose: isPlaying=${state.isPlaying}, volume=${state.volume}, pos=${state.position.inSeconds}s");
    } else {
      debugPrint("   Controller is null");
    }
    // Use async dispose pattern - cleanup will happen asynchronously
    _cleanup();
    debugPrint("🗑️  === DISPOSE CALLED (cleanup async) ===\n");
    super.dispose();
  }
}
