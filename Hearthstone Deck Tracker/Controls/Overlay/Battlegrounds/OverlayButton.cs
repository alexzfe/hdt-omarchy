using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Hearthstone_Deck_Tracker.Utility;
using Hearthstone_Deck_Tracker.Utility.Logging;

namespace Hearthstone_Deck_Tracker.Controls.Overlay.Battlegrounds;

/// <summary>
/// Button-like overlay control that avoids WPF ButtonBase click routing.
///
/// The Battlegrounds in-game overlay uses a click-through WS_EX_TRANSPARENT window model.
/// Under Wine/Linux, standard WPF Button Click/Command routing can be unreliable in that
/// window configuration even when hover/rendering still works. OverlayButton keeps the
/// ergonomic Command/Click authoring model while internally using the Border + MouseUp
/// path that works reliably in the overlay. Any mouse button counts as a click.
/// </summary>
public class OverlayButton : Border
{
	public static readonly DependencyProperty CommandProperty = DependencyProperty.Register(
		nameof(Command),
		typeof(ICommand),
		typeof(OverlayButton),
		new PropertyMetadata(null, OnCommandChanged));

	public static readonly DependencyProperty CommandParameterProperty = DependencyProperty.Register(
		nameof(CommandParameter),
		typeof(object),
		typeof(OverlayButton),
		new PropertyMetadata(null, OnCommandParameterChanged));

	public event RoutedEventHandler? Click;

	private bool _canExecute = true;

	// Under Wine's X11 driver a single physical click on the click-through overlay window arrives
	// TWICE: two MouseUp events, both ChangedButton=Left and ClickCount=1, timestamps 4 ms apart
	// and occasionally processed in reverse order (measured against the real game, 1883x1004
	// overlay). For a toggling command such as the Battlegrounds tabs the second delivery undoes
	// the first immediately, which looks like a dead button - the tab only flashes up. So drop a
	// MouseUp that repeats the last handled one within a short window. Wine only; on Windows the
	// behaviour is unchanged.
	private const int WineDuplicateClickWindowMs = 50;
	private int? _lastHandledTimestamp;

	public ICommand? Command
	{
		get => (ICommand?)GetValue(CommandProperty);
		set => SetValue(CommandProperty, value);
	}

	public object? CommandParameter
	{
		get => GetValue(CommandParameterProperty);
		set => SetValue(CommandParameterProperty, value);
	}

	// fold the command's executability into the enabled state, so a command reporting
	// CanExecute == false disables the button (like a real Button) without clobbering an
	// explicit IsEnabled binding - coercion ANDs this with the externally set value
	protected override bool IsEnabledCore => base.IsEnabledCore && _canExecute;

	private static void OnCommandChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
	{
		var button = (OverlayButton)d;
		if(e.OldValue is ICommand oldCommand)
			CanExecuteChangedEventManager.RemoveHandler(oldCommand, button.OnCanExecuteChanged);
		if(e.NewValue is ICommand newCommand)
			CanExecuteChangedEventManager.AddHandler(newCommand, button.OnCanExecuteChanged);
		button.UpdateCanExecute();
	}

	private static void OnCommandParameterChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
		=> ((OverlayButton)d).UpdateCanExecute();

	private void OnCanExecuteChanged(object? sender, EventArgs e) => UpdateCanExecute();

	private void UpdateCanExecute()
	{
		var command = Command;
		var canExecute = command == null || command.CanExecute(CommandParameter);
		if(canExecute == _canExecute)
			return;
		_canExecute = canExecute;
		CoerceValue(IsEnabledProperty);
	}

	// hook MouseUp rather than the per-button events, so left, right, middle and the
	// XButtons all trigger the button - handlers can tell them apart via ChangedButton
	protected override void OnMouseUp(MouseButtonEventArgs e)
	{
		base.OnMouseUp(e);

		if(!IsEnabled)
			return;

		if(Wine.IsWine)
		{
			if(_lastHandledTimestamp is int last && Math.Abs(e.Timestamp - last) <= WineDuplicateClickWindowMs)
			{
				Log.Debug($"Dropped duplicate MouseUp delivered by Wine (ts={e.Timestamp}, previous={last})");
				e.Handled = true;
				return;
			}
			_lastHandledTimestamp = e.Timestamp;
		}

		var command = Command;
		var commandParameter = CommandParameter;
		if(command != null && !command.CanExecute(commandParameter))
			return;

		Click?.Invoke(this, e);
		command?.Execute(commandParameter);
		// unconditionally consume the click even with no handler attached -
		// prevents the raw mouse event from passing through the overlay to the game.
		e.Handled = true;
	}
}
