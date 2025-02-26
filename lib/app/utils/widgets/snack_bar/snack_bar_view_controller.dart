import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:smart_attend/app/utils/widgets/snack_bar/snack_bar_view.dart';

class SnackBarViewController {
  static final _snackBarQueue = _SnackBarQueue();

  static bool get isSnackBarBeingShown => _snackBarQueue._isJobInProgress;
  final key = GlobalKey<SnackBarViewState>();

  late Animation<double> _filterBlurAnimation;
  late Animation<Color?> _filterColorAnimation;

  final SnackBarView snackBar;
  final _transitionCompleter = Completer();

  late SnackBarViewStatusCallback? _snackBarStatus;
  late final Alignment? _initialAlignment;
  late final Alignment? _endAlignment;

  bool _wasDismissedBySwipe = false;

  bool _onTappedDismiss = false;

  Timer? _timer;

  /// The animation that drives the route's transition and the previous route's
  /// forward transition.
  late final Animation<Alignment> _animation;

  /// The animation controller that the route uses to drive the transitions.
  ///
  /// The animation itself is exposed by the [animation] property.
  late final AnimationController _controller;

  SnackBarViewStatus? _currentStatus;

  final _overlayEntries = <OverlayEntry>[];

  OverlayState? _overlayState;

  SnackBarViewController(this.snackBar);

  Future<void> get future => _transitionCompleter.future;

  /// Close the snackBar with animation
  Future<void> close({bool withAnimations = true}) async {
    if (!withAnimations) {
      _removeOverlay();
      return;
    }
    _removeEntry();
    await future;
  }

  /// Adds SnackBarView to a view queue.
  /// Only one SnackBarView will be displayed at a time, and this method returns
  /// a future to when the snackBar disappears.
  Future<void> show() {
    return _snackBarQueue._addJob(this);
  }

  void _cancelTimer() {
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
    }
  }

  // ignore: avoid_returning_this
  void _configureAlignment(SnackBarViewPosition snackPosition) {
    switch (snackBar.snackPosition) {
      case SnackBarViewPosition.top:
        {
          _initialAlignment = const Alignment(-1.0, -2.0);
          _endAlignment = const Alignment(-1.0, -1.0);
          break;
        }
      case SnackBarViewPosition.bottom:
        {
          _initialAlignment = const Alignment(-1.0, 2.0);
          _endAlignment = const Alignment(-1.0, 1.0);
          break;
        }
    }
  }

  void _configureOverlay() {
    _overlayState = Overlay.of(Get.overlayContext!);
    _overlayEntries.clear();
    _overlayEntries.addAll(_createOverlayEntries(_getBodyWidget()));
    _overlayState!.insertAll(_overlayEntries);
    _configureSnackBarDisplay();
  }

  void _configureSnackBarDisplay() {
    assert(!_transitionCompleter.isCompleted,
        'Cannot configure a snackBar after disposing it.');
    _controller = _createAnimationController();
    _configureAlignment(snackBar.snackPosition);
    _snackBarStatus = snackBar.snackBarStatus;
    _filterBlurAnimation = _createBlurFilterAnimation();
    _filterColorAnimation = _createColorOverlayColor();
    _animation = _createAnimation();
    _animation.addStatusListener(_handleStatusChanged);
    _configureTimer();
    _controller.forward();
  }

  void _configureTimer() {
    if (snackBar.duration != null) {
      if (_timer != null && _timer!.isActive) {
        _timer!.cancel();
      }
      _timer = Timer(snackBar.duration!, _removeEntry);
    } else {
      if (_timer != null) {
        _timer!.cancel();
      }
    }
  }

  /// Called to create the animation that exposes the current progress of
  /// the transition controlled by the animation controller created by
  /// `createAnimationController()`.
  Animation<Alignment> _createAnimation() {
    assert(!_transitionCompleter.isCompleted,
        'Cannot create a animation from a disposed snackBar');
    return AlignmentTween(begin: _initialAlignment, end: _endAlignment).animate(
      CurvedAnimation(
        parent: _controller,
        curve: snackBar.forwardAnimationCurve,
        reverseCurve: snackBar.reverseAnimationCurve,
      ),
    );
  }

  /// Called to create the animation controller that will drive the transitions
  /// to this route from the previous one, and back to the previous route
  /// from this one.
  AnimationController _createAnimationController() {
    assert(!_transitionCompleter.isCompleted,
        'Cannot create a animationController from a disposed snackBar');
    assert(snackBar.animationDuration >= Duration.zero);
    return AnimationController(
      duration: snackBar.animationDuration,
      debugLabel: '$runtimeType',
      vsync: _overlayState!,
    );
  }

  Animation<double> _createBlurFilterAnimation() {
    return Tween(begin: 0.0, end: snackBar.overlayBlur).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.0,
          0.35,
          curve: Curves.easeInOutCirc,
        ),
      ),
    );
  }

  Animation<Color?> _createColorOverlayColor() {
    return ColorTween(
            begin: const Color(0x00000000), end: snackBar.overlayColor)
        .animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.0,
          0.35,
          curve: Curves.easeInOutCirc,
        ),
      ),
    );
  }

  Iterable<OverlayEntry> _createOverlayEntries(Widget child) {
    return <OverlayEntry>[
      if (snackBar.overlayBlur > 0.0) ...[
        OverlayEntry(
          builder: (context) => GestureDetector(
            onTap: () {
              if (snackBar.isDismissible && !_onTappedDismiss) {
                _onTappedDismiss = true;
                close();
              }
            },
            child: AnimatedBuilder(
              animation: _filterBlurAnimation,
              builder: (context, child) {
                return BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: max(0.001, _filterBlurAnimation.value),
                    sigmaY: max(0.001, _filterBlurAnimation.value),
                  ),
                  child: Container(
                    constraints: const BoxConstraints.expand(),
                    color: _filterColorAnimation.value,
                  ),
                );
              },
            ),
          ),
          maintainState: false,
          opaque: false,
        ),
      ],
      OverlayEntry(
        builder: (context) => Semantics(
          focused: false,
          container: true,
          explicitChildNodes: true,
          child: AlignTransition(
            alignment: _animation,
            child: snackBar.isDismissible
                ? _getDismissibleSnack(child)
                : _snackBarViewContainer(child),
          ),
        ),
        maintainState: false,
        opaque: false,
      ),
    ];
  }

  Widget _getBodyWidget() {
    return Builder(builder: (_) {
      return GestureDetector(
        onTap: snackBar.onTap != null
            ? () => snackBar.onTap?.call(snackBar)
            : null,
        child: snackBar,
      );
    });
  }

  DismissDirection _getDefaultDismissDirection() {
    if (snackBar.snackPosition == SnackBarViewPosition.top) {
      return DismissDirection.up;
    }
    return DismissDirection.down;
  }

  Widget _getDismissibleSnack(Widget child) {
    return Dismissible(
      direction: snackBar.dismissDirection ?? _getDefaultDismissDirection(),
      resizeDuration: null,
      confirmDismiss: (_) {
        if (_currentStatus == SnackBarViewStatus.opening ||
            _currentStatus == SnackBarViewStatus.closing) {
          return Future.value(false);
        }
        return Future.value(true);
      },
      key: const Key('dismissible'),
      onDismissed: (_) {
        _wasDismissedBySwipe = true;
        _removeEntry();
      },
      child: _snackBarViewContainer(child),
    );
  }

  Widget _snackBarViewContainer(Widget child) {
    return Container(
      margin: snackBar.margin,
      child: child,
    );
  }

  void _handleStatusChanged(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.completed:
        _currentStatus = SnackBarViewStatus.open;
        _snackBarStatus?.call(_currentStatus);
        if (_overlayEntries.isNotEmpty) _overlayEntries.first.opaque = false;

        break;
      case AnimationStatus.forward:
        _currentStatus = SnackBarViewStatus.opening;
        _snackBarStatus?.call(_currentStatus);
        break;
      case AnimationStatus.reverse:
        _currentStatus = SnackBarViewStatus.closing;
        _snackBarStatus?.call(_currentStatus);
        if (_overlayEntries.isNotEmpty) _overlayEntries.first.opaque = false;
        break;
      case AnimationStatus.dismissed:
        assert(!_overlayEntries.first.opaque);
        _currentStatus = SnackBarViewStatus.closed;
        _snackBarStatus?.call(_currentStatus);
        _removeOverlay();
        break;
    }
  }

  void _removeEntry() {
    assert(
      !_transitionCompleter.isCompleted,
      'Cannot remove entry from a disposed snackBar',
    );

    _cancelTimer();

    if (_wasDismissedBySwipe) {
      Timer(const Duration(milliseconds: 200), _controller.reset);
      _wasDismissedBySwipe = false;
    } else {
      _controller.reverse();
    }
  }

  void _removeOverlay() {
    for (var element in _overlayEntries) {
      element.remove();
    }

    assert(!_transitionCompleter.isCompleted,
        'Cannot remove overlay from a disposed snackBar');
    _controller.dispose();
    _overlayEntries.clear();
    _transitionCompleter.complete();
  }

  Future<void> _show() {
    _configureOverlay();
    return future;
  }

  static void cancelAllSnackBars() {
    _snackBarQueue._cancelAllJobs();
  }

  static Future<void> closeCurrentSnackBar() async {
    await _snackBarQueue._closeCurrentJob();
  }
}

class _SnackBarQueue {
  final _queue = GetQueue();
  final _snackBarList = <SnackBarViewController>[];

  SnackBarViewController? get _currentSnackBar {
    if (_snackBarList.isEmpty) return null;
    return _snackBarList.first;
  }

  bool get _isJobInProgress => _snackBarList.isNotEmpty;

  Future<void> _addJob(SnackBarViewController job) async {
    _snackBarList.add(job);
    final data = await _queue.add(job._show);
    _snackBarList.remove(job);
    return data;
  }

  Future<void> _cancelAllJobs() async {
    await _currentSnackBar?.close();
    _queue.cancelAllJobs();
    _snackBarList.clear();
  }

  Future<void> _closeCurrentJob() async {
    if (_currentSnackBar == null) return;
    await _currentSnackBar!.close();
  }
}
