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
	/// Wine's X11 driver treats layered windows differently from Windows in ways that
	/// break the transparent overlay on Wayland compositors (tested on Hyprland/XWayland):
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
		private static bool? _isWine;

		/// <summary>True when the process runs on Wine (ntdll exports wine_get_version).</summary>
		public static bool IsWine
		{
			get
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
		/// that when it would otherwise match the screen exactly.
		/// </summary>
		public static int AvoidFullScreenHeight(int top, int left, int width, int height)
		{
			if(!IsWine)
				return height;
			var screenWidth = (int)SystemParameters.PrimaryScreenWidth;
			var screenHeight = (int)SystemParameters.PrimaryScreenHeight;
			if(left <= 0 && top <= 0 && left + width >= screenWidth && top + height >= screenHeight)
				return Math.Max(0, screenHeight - top - 1);
			return height;
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
		/// Wine makes an activated popup a managed window, which the compositor then tiles.
		/// </summary>
		public static void PreventMouseActivation(Window window)
		{
			if(!IsWine)
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
		/// when it is zero). Wine turns the owner into the X11 WM_TRANSIENT_FOR hint when the window is
		/// next mapped, and Wayland compositors then keep the window stacked with its owner: whenever the
		/// game window is raised (clicked), the overlay is raised with it instead of ending up underneath.
		/// </summary>
		public static void SetOwner(Window window, IntPtr owner)
		{
			if(!IsWine)
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
		/// The X server hands each click to the topmost X window under the pointer, whatever order the
		/// compositor draws windows in. Hyprland restacks the game above the override-redirect overlay
		/// whenever it activates the game, so the overlay's buttons stop getting clicks while the overlay
		/// is still drawn on top. Skipped while the window is active, which would make Wine manage it.
		/// Wine only restacks the X window when the Win32 z-order changes, and the overlay is usually
		/// already first there (the compositor raised the game in X only), so it is briefly made
		/// non-topmost to turn the request into a real change.
		/// </summary>
		public static void RaiseWithoutActivating(Window window)
		{
			if(!IsWine)
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
