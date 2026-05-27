import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/song.dart';
import '../providers/providers.dart';

enum RepeatMode { none, one, all }

class PlaybackState {
  const PlaybackState({
    this.currentSong,
    this.queue = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isBuffering = false,
    this.volume = 1.0,
    this.isShuffled = false,
    this.repeatMode = RepeatMode.none,
  });

  final Song? currentSong;
  final List<Song> queue;
  final int currentIndex;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool isBuffering;
  final double volume;
  final bool isShuffled;
  final RepeatMode repeatMode;

  PlaybackState copyWith({
    Song? currentSong,
    bool clearSong = false,
    List<Song>? queue,
    int? currentIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? isBuffering,
    double? volume,
    bool? isShuffled,
    RepeatMode? repeatMode,
  }) =>
      PlaybackState(
        currentSong: clearSong ? null : (currentSong ?? this.currentSong),
        queue: queue ?? this.queue,
        currentIndex: currentIndex ?? this.currentIndex,
        isPlaying: isPlaying ?? this.isPlaying,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        isBuffering: isBuffering ?? this.isBuffering,
        volume: volume ?? this.volume,
        isShuffled: isShuffled ?? this.isShuffled,
        repeatMode: repeatMode ?? this.repeatMode,
      );

  bool get hasPrevious => currentIndex > 0 || repeatMode == RepeatMode.all;
  bool get hasNext =>
      currentIndex < queue.length - 1 || repeatMode == RepeatMode.all;
}

class PlaybackNotifier extends Notifier<PlaybackState> {
  late final AudioPlayer _player;
  List<Song> _originalQueue = [];

  @override
  PlaybackState build() {
    _player = AudioPlayer();
    ref.onDispose(_player.dispose);

    _player.playerStateStream.listen(_onPlayerState);
    _player.positionStream.listen(
      (p) => state = state.copyWith(position: p),
    );
    _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });

    return const PlaybackState();
  }

  void _onPlayerState(PlayerState ps) {
    state = state.copyWith(
      isPlaying: ps.playing,
      isBuffering: ps.processingState == ProcessingState.buffering ||
          ps.processingState == ProcessingState.loading,
    );
    if (ps.processingState == ProcessingState.completed) {
      if (state.repeatMode == RepeatMode.one) {
        _player.seek(Duration.zero);
        _player.play();
      } else if (state.currentIndex < state.queue.length - 1) {
        _playAtIndex(state.currentIndex + 1);
      } else if (state.repeatMode == RepeatMode.all &&
          state.queue.isNotEmpty) {
        _playAtIndex(0);
      }
    }
  }

  Future<void> playSong(Song song, {List<Song>? queue, int index = 0}) async {
    final q = queue ?? [song];
    // Entering a new queue resets shuffle so _originalQueue doesn't go stale.
    if (queue != null) {
      _originalQueue = [];
      state = state.copyWith(
        currentSong: song,
        queue: q,
        currentIndex: index,
        position: Duration.zero,
        duration: Duration.zero,
        isShuffled: false,
      );
    } else {
      state = state.copyWith(
        currentSong: song,
        queue: q,
        currentIndex: index,
        position: Duration.zero,
        duration: Duration.zero,
      );
    }
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    try {
      await _player.setUrl(repo.streamUri(song.id).toString());
      _player.play();
    } catch (_) {}
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> next() async {
    final nextIndex = state.currentIndex + 1;
    if (nextIndex < state.queue.length) {
      await _playAtIndex(nextIndex);
    } else if (state.repeatMode == RepeatMode.all && state.queue.isNotEmpty) {
      await _playAtIndex(0);
    }
  }

  Future<void> previous() async {
    if (state.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else {
      final prevIndex = state.currentIndex - 1;
      if (prevIndex >= 0) {
        await _playAtIndex(prevIndex);
      } else if (state.repeatMode == RepeatMode.all && state.queue.isNotEmpty) {
        await _playAtIndex(state.queue.length - 1);
      }
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    state = state.copyWith(volume: volume);
  }

  void toggleShuffle() {
    if (state.isShuffled) {
      // Restore original order, find current song position
      final currentSong = state.currentSong;
      final newIndex = currentSong != null
          ? _originalQueue.indexWhere((s) => s.id == currentSong.id)
          : 0;
      state = state.copyWith(
        queue: List.of(_originalQueue),
        currentIndex: newIndex < 0 ? 0 : newIndex,
        isShuffled: false,
      );
    } else {
      // Save original queue, shuffle keeping current song first
      _originalQueue = List.of(state.queue);
      final current = state.currentSong;
      final rest = state.queue.where((s) => s.id != current?.id).toList()
        ..shuffle(Random());
      final newQueue = [if (current != null) current, ...rest];
      state = state.copyWith(
        queue: newQueue,
        currentIndex: 0,
        isShuffled: true,
      );
    }
  }

  void cycleRepeat() {
    final next = switch (state.repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.none,
    };
    state = state.copyWith(repeatMode: next);
  }

  Future<void> playArtist(String artistId) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    final albums = await repo.getAlbumsByArtist(artistId);
    final allSongs = <Song>[];
    for (final album in albums) {
      final full = await repo.getAlbum(album.id);
      allSongs.addAll(full.songs);
    }
    if (allSongs.isEmpty) return;
    await playSong(allSongs.first, queue: allSongs, index: 0);
  }

  Future<void> _playAtIndex(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    await playSong(state.queue[index], queue: state.queue, index: index);
  }
}

final playbackProvider =
    NotifierProvider<PlaybackNotifier, PlaybackState>(PlaybackNotifier.new);
