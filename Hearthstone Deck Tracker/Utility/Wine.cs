using System;
using System.Runtime.InteropServices;
using System.Windows;
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

		private const uint GwOwner = 4;

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
