using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Hearthstone_Deck_Tracker.Utility.Logging;

namespace Hearthstone_Deck_Tracker.Utility
{
	/// <summary>
	/// Detection of, and workarounds for, running under Wine (Linux/macOS).
	///
	/// Two levels of detection are used:
	/// <list type="bullet">
	/// <item><see cref="IsWine"/>: any Wine. Gates the harmless changes (alpha-1 backgrounds,
	/// diagnostics).</item>
	/// <item><see cref="UsesX11Driver"/>: Wine's X11 driver (winex11.drv), i.e. X11 or XWayland.
	/// Gates everything that assumes the X11 window model and the way Wayland compositors
	/// (tested: Hyprland) treat it: override-redirect windows stacking above everything, the owner
	/// becoming WM_TRANSIENT_FOR, and the overlay never being activated. Wine's own Wayland or
	/// macOS drivers keep upstream HDT behaviour.</item>
	/// </list>
	///
	/// Wine's X11 driver treats layered windows differently from Windows in ways that
	/// break the transparent overlay on Wayland compositors:
	///
	/// - Every pixel with alpha == 0 is cut out of the X11 window's bounding shape.
	///   XWayland then never draws those pixels, and the compositor shows them as opaque
	///   black instead of see-through. Painting the window with an alpha of 1/255 keeps
	///   every pixel inside the shape while remaining visually transparent.
	///
	/// - Popup windows that are never activated, have no caption and do not cover a whole
	///   monitor are created as override-redirect ("unmanaged") X11 windows. The compositor
	///   leaves those alone: no tiling, no focus, no decorations, and they stack above a
	///   fullscreen game. That is exactly what an overlay wants, so the overlay avoids the
	///   things that would make Wine hand it to the window manager.
	/// </summary>
	public static class Wine
	{
		private static readonly object DetectionLock = new();
		private static bool? _isWine;
		private static bool? _usesX11Driver;

		/// <summary>True when the process runs on Wine (ntdll exports wine_get_version).</summary>
		public static bool IsWine
		{
			get
			{
				lock(DetectionLock)
				{
					if(_isWine.HasValue)
						return _isWine.Value;
					try
					{
						var ntdll = GetModuleHandle("ntdll.dll");
						_isWine = ntdll != IntPtr.Zero && GetProcAddress(ntdll, "wine_get_version") != IntPtr.Zero;
					}
					catch(Exception e)
					{
						Log.Warn($"Could not detect Wine: {e.Message}");
						_isWine = false;
					}
					if(_isWine.Value)
						Log.Info("Running under Wine; applying overlay workarounds");
					return _isWine.Value;
				}
			}
		}

		/// <summary>
		/// True when running under Wine's X11 driver. The driver is a PE module (winex11.drv) loaded
		/// into every GUI process once a window exists; before that, a set DISPLAY variable with no
		/// other driver loaded is taken as X11 without caching the answer.
		/// </summary>
		public static bool UsesX11Driver
		{
			get
			{
				if(!IsWine)
					return false;
				lock(DetectionLock)
				{
					if(_usesX11Driver.HasValue)
						return _usesX11Driver.Value;
					try
					{
						if(GetModuleHandle("winex11.drv") != IntPtr.Zero)
							_usesX11Driver = true;
						else if(GetModuleHandle("winewayland.drv") != IntPtr.Zero || GetModuleHandle("winemac.drv") != IntPtr.Zero)
							_usesX11Driver = false;
						else
							return !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("DISPLAY"));
					}
					catch(Exception e)
					{
						Log.Warn($"Could not detect the Wine graphics driver: {e.Message}");
						_usesX11Driver = false;
					}
					Log.Info(_usesX11Driver.Value
						? "Wine X11 driver detected; applying the X11/compositor overlay workarounds"
						: "Wine is not using its X11 driver; keeping upstream overlay window handling");
					return _usesX11Driver.Value;
				}
			}
		}

		/// <summary>Test hook: forces the detection results. Pass null for both to detect again.</summary>
		internal static void OverrideDetection(bool? isWine, bool? usesX11Driver)
		{
			lock(DetectionLock)
			{
				_isWine = isWine;
				_usesX11Driver = usesX11Driver;
			}
		}

		/// <summary>
		/// Lowest non-zero alpha. Pixels with this alpha stay inside Wine's layered window
		/// shape but are indistinguishable from fully transparent ones on screen.
		/// </summary>
		public static readonly Brush AlmostTransparentBrush = CreateAlmostTransparentBrush();

		/// <summary>
		/// Gives a window with AllowsTransparency a background that Wine keeps inside the
		/// layered window shape. Only replaces a missing or fully transparent background.
		/// </summary>
		public static void ApplyTransparencyWorkaround(Window window)
		{
			if(!IsWine)
				return;
			if(window.Background is SolidColorBrush { Color.A: > 0 })
				return;
			window.Background = AlmostTransparentBrush;
		}

		private static Brush CreateAlmostTransparentBrush()
		{
			var brush = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
			brush.Freeze();
			return brush;
		}

		/// <summary>
		/// Wine only creates a popup as an unmanaged X11 window when its rectangle does not
		/// cover a whole monitor. Returns a height that keeps the window one pixel short of
		/// that when it would otherwise cover the monitor the rectangle is on.
		/// Coordinates are WPF device-independent units, as used for Window.Top/Left/Width/Height.
		/// (In practice User32.GetHearthstoneRect already reports the client area one pixel short
		/// in both directions, so this is a safety net for rounding under DPI scaling.)
		/// </summary>
		public static int AvoidFullScreenHeight(int top, int left, int width, int height)
		{
			if(!UsesX11Driver)
				return height;
			return ClampToMonitor(top, left, width, height, MonitorBoundsDip(top, left, width, height));
		}

		/// <summary>Pure part of <see cref="AvoidFullScreenHeight"/>: <paramref name="monitor"/> is in the same units.</summary>
		internal static int ClampToMonitor(int top, int left, int width, int height, Rect monitor)
		{
			var coversMonitor = left <= monitor.Left && top <= monitor.Top
			                    && left + width >= monitor.Right && top + height >= monitor.Bottom;
			if(!coversMonitor)
				return height;
			return Math.Max(0, (int)monitor.Bottom - top - 1);
		}

		/// <summary>Bounds of the monitor containing the centre of the rectangle, in device-independent units.</summary>
		private static Rect MonitorBoundsDip(int top, int left, int width, int height)
		{
			try
			{
				var centre = new System.Drawing.Point(
					(int)((left + width / 2.0) * Helper.DpiScalingX),
					(int)((top + height / 2.0) * Helper.DpiScalingY));
				var bounds = System.Windows.Forms.Screen.FromPoint(centre).Bounds;
				return new Rect(bounds.Left / Helper.DpiScalingX, bounds.Top / Helper.DpiScalingY,
					bounds.Width / Helper.DpiScalingX, bounds.Height / Helper.DpiScalingY);
			}
			catch(Exception e)
			{
				Log.Warn($"Could not determine the game's monitor, using the primary screen: {e.Message}");
				return new Rect(0, 0, SystemParameters.PrimaryScreenWidth, SystemParameters.PrimaryScreenHeight);
			}
		}

		/// <summary>
		/// True when running under Wine and the foreground window is <paramref name="hwnd"/> or a
		/// window owned (directly or through other owners) by it, such as a WPF popup or tooltip.
		/// </summary>
		public static bool IsForegroundOwnedBy(IntPtr hwnd)
		{
			if(!IsWine || hwnd == IntPtr.Zero)
				return false;
			var window = GetForegroundWindow();
			for(var i = 0; i < 8 && window != IntPtr.Zero; i++)
			{
				if(window == hwnd)
					return true;
				window = GetWindow(window, GwOwner);
			}
			return false;
		}

		/// <summary>True when running under Wine and <paramref name="hwnd"/> is the calling thread's active window.</summary>
		public static bool IsActiveWindow(IntPtr hwnd) => IsWine && hwnd != IntPtr.Zero && GetActiveWindow() == hwnd;

		/// <summary>
		/// Answers WM_MOUSEACTIVATE with MA_NOACTIVATE so clicks on the window do not activate it.
		/// Wine's X11 driver makes an activated popup a managed window, which the compositor then tiles.
		/// </summary>
		public static void PreventMouseActivation(Window window)
		{
			if(!UsesX11Driver)
				return;
			var source = HwndSource.FromHwnd(new WindowInteropHelper(window).Handle);
			source?.AddHook((IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) =>
			{
				const int wmMouseActivate = 0x0021;
				const int maNoActivate = 3;
				if(msg != wmMouseActivate)
					return IntPtr.Zero;
				handled = true;
				return new IntPtr(maNoActivate);
			});
		}

		/// <summary>
		/// Makes <paramref name="owner"/> the Win32 owner of <paramref name="window"/> (or clears the owner
		/// when it is zero). Wine's X11 driver turns the owner into the WM_TRANSIENT_FOR hint when the
		/// window is next mapped, and Wayland compositors then keep the window stacked with its owner:
		/// whenever the game window is raised (clicked), the overlay is raised with it instead of ending
		/// up underneath. The owner lives in another process; Wine clears such an owner itself when the
		/// owner window is destroyed, so a game crash leaves the overlay unowned rather than destroyed.
		/// </summary>
		public static void SetOwner(Window window, IntPtr owner)
		{
			if(!UsesX11Driver)
				return;
			try
			{
				new WindowInteropHelper(window).Owner = owner;
			}
			catch(Exception e)
			{
				Log.Warn($"Could not set the window owner: {e.Message}");
			}
		}

		/// <summary>
		/// Puts <paramref name="window"/> at the top of the X11 stacking order without activating it.
		/// The X server hands each click to the topmost X window under the pointer that accepts input,
		/// whatever order the compositor draws windows in. Hyprland restacks a managed X11 window to the
		/// top whenever it activates it (XWaylandManager activateSurface), so after the game is clicked,
		/// dragged or focused the overlay sits below it in X: still drawn on top (pinned), hover works,
		/// but clicks on its buttons go to the game. Evidence (2026-09-12, real game): a query_pointer
		/// probe showed the order flip, and Battlegrounds tab clicks were logged only after this raise
		/// was added. A single SetWindowPos(HWND_TOPMOST) is a no-op when the window is already topmost
		/// (win32u adds SWP_NOZORDER), so the window goes non-topmost first to make the second call a
		/// real z-order change that Wine emits as XConfigureWindow(Above). Skipped while the window is
		/// the active window, when a SetWindowPos would let Wine turn it into a managed window.
		/// </summary>
		public static void RaiseWithoutActivating(Window window)
		{
			if(!UsesX11Driver)
				return;
			var hwnd = new WindowInteropHelper(window).Handle;
			if(hwnd == IntPtr.Zero || IsActiveWindow(hwnd))
				return;
			const uint flags = SwpNoSize | SwpNoMove | SwpNoActivate | SwpNoOwnerZOrder;
			User32.SetWindowPos(hwnd, HwndNoTopmost, 0, 0, 0, 0, flags);
			User32.SetWindowPos(hwnd, HwndTopmost, 0, 0, 0, 0, flags);
		}

		private static readonly IntPtr HwndTopmost = new(-1);
		private static readonly IntPtr HwndNoTopmost = new(-2);
		private const uint SwpNoSize = 0x0001;
		private const uint SwpNoMove = 0x0002;
		private const uint SwpNoActivate = 0x0010;
		private const uint SwpNoOwnerZOrder = 0x0200;

		/// <summary>Handle, title, class, process and owner of a window, for diagnostic log lines.</summary>
		public static string DescribeWindow(IntPtr hwnd)
		{
			if(hwnd == IntPtr.Zero)
				return "no window";
			var title = new StringBuilder(128);
			GetWindowText(hwnd, title, title.Capacity);
			var className = new StringBuilder(128);
			GetClassName(hwnd, className, className.Capacity);
			GetWindowThreadProcessId(hwnd, out var pid);
			var owner = GetWindow(hwnd, GwOwner);
			var ownerText = owner == IntPtr.Zero ? "" : $", owner 0x{owner.ToInt64():x}";
			return $"0x{hwnd.ToInt64():x} '{title}' ({className}, pid {pid}{ownerText})";
		}

		/// <summary>See <see cref="DescribeWindow"/>; describes the current foreground window.</summary>
		public static string DescribeForeground() => DescribeWindow(GetForegroundWindow());

		private const uint GwOwner = 4;

		[DllImport("user32.dll", CharSet = CharSet.Unicode)]
		private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

		[DllImport("user32.dll", CharSet = CharSet.Unicode)]
		private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

		[DllImport("user32.dll")]
		private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

		[DllImport("user32.dll")]
		private static extern IntPtr GetActiveWindow();

		[DllImport("user32.dll")]
		private static extern IntPtr GetForegroundWindow();

		[DllImport("user32.dll")]
		private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

		[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
		private static extern IntPtr GetModuleHandle(string lpModuleName);

		[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
		private static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);
	}
}
