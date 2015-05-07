/*-
 * Copyright (c) 2015 Wingpanel Developers (http://launchpad.net/wingpanel)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Library General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

public class Wingpanel.IndicatorManager : GLib.Object {
	private static Wingpanel.IndicatorManager? indicator_manager = null;

	public static IndicatorManager get_default () {
		if (indicator_manager == null)
			indicator_manager = new IndicatorManager ();

		return indicator_manager;
	}

	[CCode (has_target = false)]
	private delegate Wingpanel.Indicator RegisterPluginFunction (Module module);

	private Gee.HashMap<string, Wingpanel.Indicator> indicators;

	private FileMonitor? monitor = null;

	public signal void indicator_added (Wingpanel.Indicator indicator);
	public signal void indicator_removed (Wingpanel.Indicator indicator);

	private IndicatorManager () {
		indicators = new Gee.HashMap<string, Wingpanel.Indicator> ();

		var base_folder = File.new_for_path (Build.INDICATORS_DIR);

		try {
			monitor = base_folder.monitor_directory (FileMonitorFlags.NONE, null);
			monitor.changed.connect ((file, trash, event) => {
				var plugin_path = file.get_path ();

				if (event == FileMonitorEvent.CHANGES_DONE_HINT) {
					// FIXME: Reloading the plugin does not update the indicator and only registers it again.
					// See module.make_resident ()
					load (plugin_path);
				} else if (event == FileMonitorEvent.DELETED) {
					deregister_indicator (plugin_path, indicators.@get (plugin_path));
				}
			});
		} catch (Error error) {
			warning ("Creating monitor for %s failed: %s\n", base_folder.get_path (), error.message);
		}

		find_plugins (base_folder);
	}

	private void load (string path) {
		if (!Module.supported ())
			error ("Wingpanel is not supported by this system!");

		Module module = Module.open (path, ModuleFlags.BIND_LAZY);
		if (module == null) {
			critical (Module.error ());

			return;
		}

		void* function;

		if (!module.symbol ("get_indicator", out function))
			return;

		if (function == null) {
			critical ("get_indicator () not found in %s", path);

			return;
		}

		RegisterPluginFunction register_plugin = (RegisterPluginFunction) function;
		Wingpanel.Indicator indicator = register_plugin (module);

		if (indicator == null) {
			critical ("Unknown plugin type for %s !", path);

			return;
		}

		module.make_resident ();
		register_indicator (path, indicator);
	}

	private void find_plugins (File base_folder) {
		FileInfo file_info = null;

		try {
			var enumerator = base_folder.enumerate_children (FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_CONTENT_TYPE, 0);

			while ((file_info = enumerator.next_file ()) != null) {
				var file = base_folder.get_child (file_info.get_name ());

				if (file_info.get_file_type () == FileType.REGULAR && GLib.ContentType.equals (file_info.get_content_type (), "application/x-sharedlib"))
					load (file.get_path ());
				else if (file_info.get_file_type () == FileType.DIRECTORY)
					find_plugins (file);
			}
		} catch (Error error) {
			warning ("Unable to scan indicators folder %s: %s\n", base_folder.get_path (), error.message);
		}
	}

	public void register_indicator (string path, Wingpanel.Indicator indicator) {
		debug ("%s registered", indicator.code_name);

		indicators.@foreach ((entry) => {
			if (entry.value.code_name == indicator.code_name)
				deregister_indicator (entry.key, entry.value);

			return true;
		});

		indicators.@set (path, indicator);

		indicator_added (indicator);
	}

	public void deregister_indicator (string path, Wingpanel.Indicator indicator) {
		debug ("%s deregistered", indicator.code_name);

		if (!indicators.has_key (path))
			return;

		if (indicators.unset (path))
			indicator_removed (indicator);
	}

	public bool has_indicators () {
		return !indicators.is_empty;
	}

	public Gee.Collection<Wingpanel.Indicator> get_indicators () {
		return indicators.values.read_only_view;
	}
}