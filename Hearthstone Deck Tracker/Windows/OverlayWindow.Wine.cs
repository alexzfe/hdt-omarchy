using System;
using System.Windows.Interop;
using System.Windows.Threading;
using Hearthstone_Deck_Tracker.Utility;
using Hearthstone_Deck_Tracker.Utility.Logging;

namespace Hearthstone_Deck_Tracker.Windows
{
	/// <summary>
	/// The Linux/Wine half of the overlay window. Everything here is a no-op on Windows: each entry
	/// point either self-gates on <see cref="Wine.IsWine"/> / <see cref="Wine.UsesX11Driver"/> or
	/// delegates to a helper in <see cref="Wine"/> that does. It lives in its own partial so the
	/// upstream overlay files keep a handful of one-line call sites instead of inline workarounds,
	/// which is what makes merging upstream releases cheap. See Utility/Wine.cs for the why of each
	/// workaround, and linux/README.md for the whole picture.
	/// </summary>
	public partial class OverlayWindow
	{
		private DispatcherTimer? _gameRectPoller;
		private System.Drawing.Rectangle _lastPolledGameRect;
		private int _foregroundHandBackAttempts;
		private const int MaxForegroundHandBackAttempts = 8; // 2 s at the 250 ms poll interval
		private IntPtr _ownedGameWindow;

		/// <summary>Set while the overlay is in the Behind state under Wine's X11 driver; see UpdateVisibility.</summary>
		private bool _hiddenBehindGame;

		/// <summary>
		/// An alpha of 1/255 keeps every pixel inside Wine's layered window shape (alpha 0 would render
		/// as opaque black under XWayland), and never activating on Show() lets Wine keep this window
		/// override-redirect, so the compositor stacks it above the game without tiling or focusing it.
		/// </summary>
		private void InitializeWineOverlay()
		{
			if(!Wine.IsWine)
				return;
			Wine.ApplyTransparencyWorkaround(this);
			ShowActivated = false;
		}

		/// <summary>True while the rectangle poller stands in for the window hook; see OnGameWindowHookFailed.</summary>
		private bool IsPollingGameRect => _gameRectPoller != null;

		/// <summary>
		/// Under Wine's X11 driver the game window becomes the overlay's owner so the compositor stacks
		/// the overlay with the game (see <see cref="Wine.SetOwner"/>). Cleared in OnGameWindowUnhooked.
		/// </summary>
		private void OnGameWindowHooking()
		{
			if(!Wine.UsesX11Driver)
				return;
			_ownedGameWindow = User32.GetHearthstoneWindow();
			Wine.SetOwner(this, _ownedGameWindow);
			Log.Info("Game window set as the overlay owner");
		}

		/// <summary>
		/// Without the hook the overlay would never follow the game window again. This happens under Wine,
		/// whose server refuses an out-of-context hook on another process's thread when no module handle is
		/// given. Fall back to watching the window rectangle. On Windows the hook can fail for reasons the
		/// polling would not fix (an elevated game, UIPI), so keep upstream's behaviour there rather than
		/// running a timer that may Hide()/Show() the window and drop OBS's capture.
		/// </summary>
		private void OnGameWindowHookFailed()
		{
			if(!Wine.IsWine)
				return;
			Log.Warn("Could not hook the Hearthstone window, polling its position instead");
			StartGameRectPolling();
		}

		private void OnGameWindowUnhooked()
		{
			Wine.SetOwner(this, IntPtr.Zero);
			_ownedGameWindow = IntPtr.Zero;
			_foregroundHandBackAttempts = 0;
			if(_gameRectPoller == null)
				return;
			_gameRectPoller.Stop();
			_gameRectPoller = null;
		}

		private void StartGameRectPolling()
		{
			_lastPolledGameRect = User32.GetHearthstoneRect(true);
			_gameRectPoller = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(250) };
			_gameRectPoller.Tick += (_, _) => PollGameRect();
			_gameRectPoller.Start();
		}

		private void PollGameRect()
		{
			var gameWindow = User32.GetHearthstoneWindow();
			if(gameWindow == IntPtr.Zero)
				return;
			// Only when we already own a window: _ownedGameWindow is set in OnGameWindowHooking, and only
			// under the X11 driver, where owning the game window is what SetOwner does. Without this the
			// first tick would always look like a game restart.
			if(_ownedGameWindow != IntPtr.Zero && gameWindow != _ownedGameWindow)
			{
				// A new game window (quick restart): re-own and remap so Wine refreshes the
				// WM_TRANSIENT_FOR hint, which it only writes when the window is mapped.
				Wine.SetOwner(this, gameWindow);
				_ownedGameWindow = gameWindow;
				if(IsVisible)
				{
					Log.Info("Game window changed, remapping the overlay under the new owner");
					Hide();
					Show();
				}
			}
			var rect = User32.GetHearthstoneRect(true);
			if(rect == _lastPolledGameRect)
				return;
			// Wine turns a popup that is moved while it is the active window into a managed window. Hand
			// activation back to the game first and retry on the next tick, a bounded number of times so
			// this can never turn into a focus-stealing loop.
			if(Wine.IsActiveWindow(new WindowInteropHelper(this).Handle))
			{
				if(_foregroundHandBackAttempts < MaxForegroundHandBackAttempts)
				{
					if(_foregroundHandBackAttempts == 0)
						Log.Info("Overlay is the active window, giving the game the foreground before moving");
					_foregroundHandBackAttempts++;
					User32.BringHsToForeground();
				}
				else if(_foregroundHandBackAttempts == MaxForegroundHandBackAttempts)
				{
					_foregroundHandBackAttempts++;
					Log.Warn($"Overlay is still the active window after {MaxForegroundHandBackAttempts} attempts to give the game the foreground; waiting");
				}
				return;
			}
			_foregroundHandBackAttempts = 0;
			Log.Debug($"Game window moved to {rect}, updating overlay position");
			_lastPolledGameRect = rect;
			UpdatePosition();
			// moving or resizing the game restacks it above the overlay in X, see Wine.RaiseWithoutActivating
			Wine.RaiseWithoutActivating(this);
		}

		/// <summary>
		/// Wine's override-redirect overlay is drawn above every other window by Wayland compositors, so
		/// sending it behind the game does nothing there; hide the content instead. The flag feeds
		/// <see cref="ApplyOpacity"/>, the single place that decides the window's opacity, so no other code
		/// path (ShowOverlay, Update) can make a "behind" overlay visible between two ticks.
		/// </summary>
		private void UpdateWineHiddenState(OverlayZState newState)
			=> _hiddenBehindGame = Wine.UsesX11Driver && newState == OverlayZState.Behind;

		/// <summary>
		/// The one place that decides the overlay window's opacity: the configured overlay opacity while
		/// content is visible, zero when it is not or when Wine hides it behind the game.
		/// </summary>
		internal void ApplyOpacity()
			=> Opacity = IsContentVisible && !_hiddenBehindGame ? Config.Instance.OverlayOpacity / 100 : 0;

		/// <summary>
		/// Under Wine's X11 driver a popup covering the whole monitor is handed to the window manager;
		/// staying a pixel short keeps it override-redirect. The canvas keeps the full size.
		/// </summary>
		private double WineAdjustedHeight(int top, int left, int width, int height)
			=> Wine.AvoidFullScreenHeight(top, left, width, height);

		private void LogOverlayRect(int top, int left, int width, int height)
		{
			if(Wine.IsWine)
				Log.Debug($"Overlay rect set to {left},{top} {width}x{Height} (game {width}x{height}, opacity {Opacity:0.##}, mapped {IsVisible})");
		}

		private void LogOverlayStateChange(OverlayZState from, OverlayZState to, bool gameIsForeground)
		{
			if(Wine.IsWine)
				Log.Info($"Overlay {from} -> {to} (game foreground: {gameIsForeground}, foreground window: {Wine.DescribeForeground()})");
		}

		/// <summary>
		/// Under Wine, focus given to the overlay or one of its popups (tooltips etc.) must not count as
		/// the game going into the background, or the overlay would blink on every hover.
		/// </summary>
		private bool WineOwnsForeground() => Wine.IsForegroundOwnedBy(new WindowInteropHelper(this).Handle);
	}
}
