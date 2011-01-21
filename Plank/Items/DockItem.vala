//  
//  Copyright (C) 2011 Robert Dyer
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
// 

using Gdk;
using Gtk;

using Plank.Drawing;
using Plank.Services;
using Plank.Services.Windows;

namespace Plank.Items
{
	public enum IndicatorState
	{
		NONE,
		SINGLE,
		SINGLE_PLUS,
	}
	
	public enum ItemState
	{
		NORMAL,
		ACTIVE,
		URGENT,
	}
	
	public enum ClickAnimation
	{
		NONE,
		BOUNCE,
		DARKEN,
		LIGHTEN
	}
	
	public class DockItem : GLib.Object
	{
		public signal void launcher_changed (DockItem item);
		
		public Bamf.Application? App { get; set; }
		
		public string Icon { get; set; default = "folder"; }
		
		public string Text { get; set; default = ""; }
		
		public int Position { get; set; default = 0; }
		
		public ItemState State { get; protected set; default = ItemState.NORMAL; }
		
		public IndicatorState Indicator { get; protected set; default = IndicatorState.NONE; }
		
		public ClickAnimation ClickedAnimation { get; protected set; default = ClickAnimation.NONE; }
		
		public DateTime LastClicked { get; protected set; default = new DateTime.from_unix_utc (0); }
		
		public DateTime LastUrgent { get; protected set; default = new DateTime.from_unix_utc (0); }
		
		public DateTime LastActive { get; protected set; default = new DateTime.from_unix_utc (0); }
		
		public bool ValidItem {
			get { return File.new_for_path (Prefs.Launcher).query_exists (); }
		}
		
		protected DockItemPreferences Prefs { get; protected set; }
		
		public DockItem ()
		{
			Prefs = new DockItemPreferences ();
			
			Prefs.notify["Launcher"].connect (() => launcher_changed (this));
		}
		
		public int get_sort ()
		{
			return Prefs.Sort;
		}
		
		public void set_sort (int pos)
		{
			if (Prefs.Sort!= pos)
				Prefs.Sort = pos;
		}
		
		public string get_launcher ()
		{
			return Prefs.Launcher;
		}
		
		public void launch ()
		{
			Services.System.launch (File.new_for_path (get_launcher ()), {});
		}
		
		public void set_app (Bamf.Application? app)
		{
			if (App != null) {
				App.active_changed.disconnect (update_active);
				App.running_changed.disconnect (update_app);
				App.closed.disconnect (update_app);
				App.urgent_changed.disconnect (update_urgent);
			}
			
			App = app;
			
			update_states ();
			
			if (app != null) {
				app.active_changed.connect (update_active);
				app.running_changed.connect (update_app);
				app.closed.connect (update_app);
				app.urgent_changed.connect (update_urgent);
			}
		}
		
		public void update_app ()
		{
			set_app (Matcher.get_default ().app_for_launcher (get_launcher ()));
		}
		
		public void update_urgent ()
		{
			var was_urgent = (State & ItemState.URGENT) != 0;
			
			if (App == null || App.is_closed () || !App.is_running ()) {
				if ((State & ItemState.URGENT) != 0)
					State &= ~ItemState.URGENT;
			} else {
				if (App.is_urgent ())
					State |= ItemState.URGENT;
				else
					State &= ~ItemState.URGENT;
			}
			
			if (was_urgent != ((State & ItemState.URGENT) != 0))
				LastUrgent = new DateTime.now_utc ();
		}
		
		public void update_indicator ()
		{
			if (App == null || App.is_closed () || !App.is_running ()) {
				Indicator = IndicatorState.NONE;
				return;
			}
			
			// set running
			if (WindowControl.get_num_windows (App) > 1)
				Indicator = IndicatorState.SINGLE_PLUS;
			else
				Indicator = IndicatorState.SINGLE;
		}
		
		public void update_active ()
		{
			var was_active = (State & ItemState.ACTIVE) != 0;
			
			if (App == null || App.is_closed () || !App.is_running ()) {
				if (was_active)
					LastActive = new DateTime.now_utc ();
				State = ItemState.NORMAL;
			} else {
				// set active
				if (App.is_active ())
					State |= ItemState.ACTIVE;
				else
					State &= ~ItemState.ACTIVE;
			}
			
			if (was_active != ((State & ItemState.ACTIVE) != 0))
				LastActive = new DateTime.now_utc ();
		}
		
		public void update_states ()
		{
			update_urgent ();
			update_indicator ();
			update_active ();
		}
		
		public void clicked (uint button, ModifierType mod)
		{
			ClickedAnimation = on_clicked (button, mod);
			LastClicked = new DateTime.now_utc ();
		}
		
		protected virtual ClickAnimation on_clicked (uint button, ModifierType mod)
		{
			if (is_plank_item ()) {
				Plank.show_about ();
				return ClickAnimation.DARKEN;
			}
			
			if (((App == null || App.get_children ().length () == 0) && button == 1) ||
				button == 2 || 
				(button == 1 && (mod & ModifierType.CONTROL_MASK) == ModifierType.CONTROL_MASK)) {
				launch ();
				return ClickAnimation.BOUNCE;
			}
			
			if ((App == null || App.get_children ().length () == 0) || button != 1)
				return ClickAnimation.NONE;
			
			WindowControl.smart_focus (App);
			
			return ClickAnimation.DARKEN;
		}
		
		bool is_plank_item ()
		{
			return get_launcher ().has_suffix ("plank.desktop");
		}
		
		public virtual List<MenuItem> get_menu_items ()
		{
			if (is_plank_item ())
				return get_plank_items ();
			
			List<MenuItem> items = new List<MenuItem> ();
			
			if (App == null || App.get_children ().length () == 0) {
				var item = new ImageMenuItem.from_stock (STOCK_OPEN, null);
				item.activate.connect (() => launch ());
				items.append (item);
			} else {
				var item = add_menu_item (items, "New _Window", "document-open-symbolic;;document-open");
				item.activate.connect (() => launch ());
				items.append (item);
				
				item = add_menu_item (items, "Ma_ximize", "view-fullscreen");
				item.activate.connect (() => WindowControl.maximize (App));
				items.append (item);
				
				item = add_menu_item (items, "Mi_nimize", "view-restore");
				item.activate.connect (() => WindowControl.minimize (App));
				items.append (item);
				
				item = add_menu_item (items, "_Close All", "window-close-symbolic;;window-close");
				item.activate.connect (() => WindowControl.close_all (App));
				items.append (item);
				
				List<Bamf.Window> windows = WindowControl.get_windows (App);
				if (windows.length () > 0) {
					items.append (new SeparatorMenuItem ());
					
					int width, height;
					icon_size_lookup (IconSize.MENU, out width, out height);
					
					for (int i = 0; i < windows.length (); i++) {
						var window = windows.nth_data (i);
						
						var pbuf = WindowControl.get_window_icon (window);
						if (pbuf == null)
							DrawingService.load_icon (Icon, width, height);
						else
							pbuf = DrawingService.ar_scale (pbuf, width, height);
						
						var window_item = new ImageMenuItem.with_mnemonic (window.get_name ());
						window_item.set_image (new Gtk.Image.from_pixbuf (pbuf));
						window_item.activate.connect (() => WindowControl.focus_window (window));
						items.append (window_item);
					}
				}
			}
			
			return items;
		}
		
		public virtual string unique_id ()
		{
			return "dockitem%d".printf ((int) this);
		}
		
		public string as_uri ()
		{
			return "plank://" + unique_id ();
		}
		
		MenuItem add_menu_item (List<MenuItem> items, string title, string icon)
		{
			int width, height;
			var item = new ImageMenuItem.with_mnemonic (title);
			
			icon_size_lookup (IconSize.MENU, out width, out height);
			item.set_image (new Gtk.Image.from_pixbuf (DrawingService.load_icon (icon, width, height)));
			
			return item;
		}
		
		List<MenuItem> get_plank_items ()
		{
			List<MenuItem> items = new List<MenuItem> ();
			
			var item = new ImageMenuItem.from_stock (STOCK_ABOUT, null);
			item.activate.connect (() => Plank.show_about ());
			items.append (item);
			
			item = new ImageMenuItem.from_stock (STOCK_QUIT, null);
			item.activate.connect (() => Plank.quit ());
			items.append (item);
			
			return items;
		}
	}
}
