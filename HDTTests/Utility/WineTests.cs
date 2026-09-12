using System.Windows;
using Hearthstone_Deck_Tracker.Utility;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace HDTTests.Utility
{
	[TestClass]
	public class WineTests
	{
		private static readonly Rect Primary = new Rect(0, 0, 1920, 1200);

		[TestMethod]
		public void ClampToMonitor_LeavesAWindowedGameAlone()
		{
			// the Super+O pop-out size: 1300x900 centred, client rect one pixel short
			Assert.AreEqual(899, Wine.ClampToMonitor(163, 310, 1299, 899, Primary));
		}

		[TestMethod]
		public void ClampToMonitor_ShortensAWindowCoveringTheMonitor()
		{
			Assert.AreEqual(1199, Wine.ClampToMonitor(0, 0, 1920, 1200, Primary));
		}

		[TestMethod]
		public void ClampToMonitor_UsesTheMonitorTheGameIsOn()
		{
			var secondary = new Rect(1920, 0, 1920, 1080);
			Assert.AreEqual(1079, Wine.ClampToMonitor(0, 1920, 1920, 1080, secondary));
			// the same rectangle measured against the primary monitor does not cover it
			Assert.AreEqual(1080, Wine.ClampToMonitor(0, 1920, 1920, 1080, Primary));
		}

		[TestMethod]
		public void ClampToMonitor_HandlesMonitorsAtNegativeCoordinates()
		{
			var left = new Rect(-1920, 0, 1920, 1080);
			Assert.AreEqual(1079, Wine.ClampToMonitor(0, -1920, 1920, 1080, left));
		}

		[TestMethod]
		public void ClampToMonitor_NeverReturnsANegativeHeight()
		{
			Assert.IsTrue(Wine.ClampToMonitor(1200, 0, 1920, 1, new Rect(0, 0, 1920, 1200)) >= 0);
		}

		[TestMethod]
		public void AvoidFullScreenHeight_IsIdentityOffWine()
		{
			Wine.OverrideDetection(false, false);
			try
			{
				Assert.AreEqual(1200, Wine.AvoidFullScreenHeight(0, 0, 1920, 1200));
			}
			finally
			{
				Wine.OverrideDetection(null, null);
			}
		}

		[TestMethod]
		public void UsesX11Driver_IsFalseOffWine()
		{
			Wine.OverrideDetection(false, null);
			try
			{
				Assert.IsFalse(Wine.UsesX11Driver);
			}
			finally
			{
				Wine.OverrideDetection(null, null);
			}
		}

		[TestMethod]
		public void UsesX11Driver_FollowsTheOverride()
		{
			Wine.OverrideDetection(true, false);
			try
			{
				Assert.IsTrue(Wine.IsWine);
				Assert.IsFalse(Wine.UsesX11Driver);
			}
			finally
			{
				Wine.OverrideDetection(null, null);
			}
		}
	}
}
