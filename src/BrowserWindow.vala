/**
* This file is part of Odysseus Web Browser (Copyright Adrian Cochrane 2016).
*
* Oddysseus is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Oddysseus is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.

* You should have received a copy of the GNU General Public License
* along with Oddysseus.  If not, see <http://www.gnu.org/licenses/>.
*/
public class Odysseus.BrowserWindow : Gtk.Window {
    private weak Odysseus.Application app;

    private WebKit.WebView web;
    private Granite.Widgets.DynamicNotebook tabs;
    private DownloadsBar downloads;

    private ButtonWithMenu back;
    private ButtonWithMenu forward;
    private Gtk.Button reload;
    private Gtk.Button stop;
    private Gtk.Stack reload_stop;
    private AddressBar addressbar;

    private Gee.List<ulong> web_event_handlers;
    private Gee.List<Binding> bindings;

    public BrowserWindow(Odysseus.Application ody_app) {
        this.app = ody_app;
        set_application(this.app);
        this.title = "(Loading)";
        this.icon_name = "internet-web-browser";

        setup_webcontext();
        init_layout();
        register_events();
        create_accelerators();
    }

    private void setup_webcontext() {
        var ctx = WebKit.WebContext.get_default();
        ctx.set_favicon_database_directory(null); // to fix favicon loading
        ctx.download_started.connect((download) => {
            downloads.add_entry(new DownloadButton(download));
        });
    }

    private void init_layout() {
        back = new ButtonWithMenu.from_icon_name ("go-previous-symbolic",
                                                Gtk.IconSize.LARGE_TOOLBAR);
        forward = new ButtonWithMenu.from_icon_name ("go-next-symbolic",
                                                Gtk.IconSize.LARGE_TOOLBAR);
        reload = new Gtk.Button.from_icon_name ("view-refresh-symbolic",
                                                Gtk.IconSize.LARGE_TOOLBAR);
        stop = new Gtk.Button.from_icon_name ("process-stop-symbolic",
                                                Gtk.IconSize.LARGE_TOOLBAR);
        reload_stop = new Gtk.Stack();
        reload_stop.add_named (reload, "reload");
        reload_stop.add_named (stop, "stop");
        addressbar = new Odysseus.AddressBar();

        var appmenu = new Granite.Widgets.AppMenu(create_appmenu());

        Gtk.HeaderBar header = new Gtk.HeaderBar();
        header.show_close_button = true;
        header.pack_start(back);
        header.pack_start(forward);
        header.pack_start(reload_stop);
        header.set_custom_title(addressbar);
        header.pack_end(appmenu);
        header.set_has_subtitle(false);
        set_titlebar(header);

        var container = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        this.add(container);

        tabs = new Granite.Widgets.DynamicNotebook();
        tabs.allow_drag = true;
        //tabs.allow_duplication = true; // TODO implement
        tabs.allow_new_window = true;
        tabs.allow_pinning = true;
        //tabs.allow_restoring = true; // TODO implement
        tabs.group_name = "odysseus-web-browser";
        container.pack_start(tabs);
        
        downloads = new DownloadsBar();
        downloads.transition_type = Gtk.RevealerTransitionType.SLIDE_UP;
        container.pack_end(downloads, false);
    }

    private Gtk.MenuItem open_item;
    private Gtk.MenuItem save_item;
    
    private Gtk.Menu create_appmenu() {
        var menu = new Gtk.Menu();

        // TODO translate
        var new_window = new Gtk.MenuItem.with_label("New Window");
        new_window.activate.connect(() => {
            var window = new BrowserWindow(Odysseus.Application.instance);
            window.show_all();
        });
        menu.add(new_window);

        // TODO translate
        var open = new Gtk.MenuItem.with_label("Open...");
        open.activate.connect(() => {
            var chooser = new Gtk.FileChooserDialog(
                                "Open Local Webpage", // TODO translate
                                this,
                                Gtk.FileChooserAction.OPEN,
                                Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                                Gtk.Stock.OPEN, Gtk.ResponseType.OK);
            chooser.filter.add_mime_type("text/html");
            chooser.filter.add_mime_type("application/xhtml+xml");
            chooser.filter.add_pattern("*.html");
            chooser.filter.add_pattern("*.htm");
            chooser.filter.add_pattern("*.xhtml");

            if (chooser.run() == Gtk.ResponseType.OK) {
                foreach (string uri in chooser.get_uris()) {
                    new_tab(uri);
                }
            }
            chooser.destroy();
        });
        menu.add(open);
        open_item = open;

        // TODO translate
        var save = new Gtk.MenuItem.with_label("Save...");
        save.activate.connect(() => {
            var chooser = new Gtk.FileChooserDialog(
                                "Save Page as", // TODO translate
                                this,
                                Gtk.FileChooserAction.SAVE,
                                Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                                Gtk.Stock.SAVE_AS, Gtk.ResponseType.OK);

            if (chooser.run() == Gtk.ResponseType.OK) {
                web.save_to_file(File.new_for_uri(chooser.get_uri()),
                                                    WebKit.SaveMode.MHTML, null);
            }
            chooser.destroy();
        });
        menu.add(save);
        save_item = save;

        menu.add(new Gtk.SeparatorMenuItem());

        // TODO translate
        var zoomin = new Gtk.MenuItem.with_label("Zoom in");
        zoomin.activate.connect(() => {
            web.zoom_level += 0.1;
        });
        menu.add(zoomin);

        var zoomout = new Gtk.MenuItem.with_label("Zoom out");
        zoomout.activate.connect(() => {
            web.zoom_level -= 0.1;
        });
        menu.add(zoomout);

        menu.add(new Gtk.SeparatorMenuItem());

        // TODO translate
        var find_in_page = new Gtk.MenuItem.with_label("Find In Page...");
        find_in_page.activate.connect(find_in_page_cb);
        menu.add(find_in_page);

        var print = new Gtk.MenuItem.with_label("Print...");
        print.activate.connect(() => {
            var printer = new WebKit.PrintOperation(web);
            printer.run_dialog(this);
        });
        menu.add(print);
        
        menu.show_all();
        return menu;
    }

    private void register_events() {
        web_event_handlers = new Gee.ArrayList<ulong>();
        bindings = new Gee.ArrayList<Binding>();

        back.button_release_event.connect((e) => {
            web.go_back();
            return false;
        });
        forward.button_release_event.connect((e) => {
            web.go_forward();
            return false;
        });
        back.fetcher = () => {
            var history = web.get_back_forward_list();
            return build_history_menu(history.get_back_list());
        };
        forward.fetcher = () => {
            var history = web.get_back_forward_list();
            return build_history_menu(history.get_forward_list());
        };
        reload.clicked.connect(() => {web.reload();});
        stop.clicked.connect(() => {web.stop_loading();});
        addressbar.activate.connect(() => {
            web.load_uri(addressbar.text);
        });

        tabs.tab_switched.connect((old_tab, new_tab) => {
            if (web != null) disconnect_webview();
            web = ((WebTab) new_tab).web;
            connect_webview((WebTab) new_tab);
        });
        tabs.new_tab_requested.connect(() => {
            var tab = new WebTab(tabs);
            tabs.insert_tab(tab, -1);
            tabs.current = tab;
        });
        // Ensure a tab is always open
        tabs.tab_removed.connect((tab) => {
            if (tabs.n_tabs == 0) tabs.new_tab_requested();
        });
        tabs.show.connect(() => {
            if (tabs.n_tabs == 0) tabs.new_tab_requested();
        });
    }
    
    private void create_accelerators() {
        var accel = new Gtk.AccelGroup();

        accel.connect(Gdk.Key.F, Gdk.ModifierType.CONTROL_MASK,
                        Gtk.AccelFlags.VISIBLE | Gtk.AccelFlags.LOCKED,
                        (group, acceleratable, key, modifier) => {
            find_in_page_cb();
            return true;
        });
        accel.connect(Gdk.Key.T, Gdk.ModifierType.CONTROL_MASK,
                        Gtk.AccelFlags.VISIBLE | Gtk.AccelFlags.LOCKED,
                        (group, acceleratable, key, modifier) => {
            new_tab();
            return true;
        });
        accel.connect(Gdk.Key.N, Gdk.ModifierType.CONTROL_MASK,
                        Gtk.AccelFlags.VISIBLE | Gtk.AccelFlags.LOCKED,
                        (group, acceleratable, key, modifier) => {
            new BrowserWindow(Odysseus.Application.instance);
            return true;
        });
        accel.connect(Gdk.Key.P, Gdk.ModifierType.CONTROL_MASK,
                        Gtk.AccelFlags.VISIBLE | Gtk.AccelFlags.LOCKED,
                        (group, acceleratable, key, modifier) => {
            var printer = new WebKit.PrintOperation(web);
            printer.run_dialog(this);
            return true;
        });

        accel.connect(Gdk.Key.O, Gdk.ModifierType.CONTROL_MASK,
                        Gtk.AccelFlags.VISIBLE | Gtk.AccelFlags.LOCKED,
                        (group, acceleratable, key, modifier) => {
            open_item.activate();
            return true;
        });
        accel.connect(Gdk.Key.S, Gdk.ModifierType.CONTROL_MASK,
                        Gtk.AccelFlags.VISIBLE | Gtk.AccelFlags.LOCKED,
                        (group, acceleratable, key, modifier) => {
            save_item.activate();
            return true;
        });

        accel.connect(Gdk.Key.minus, Gdk.ModifierType.CONTROL_MASK,
                        Gtk.AccelFlags.VISIBLE | Gtk.AccelFlags.LOCKED,
                        (group, acceleratable, key, modifier) => {
            web.zoom_level -= 0.1;
            return true;
        });
        accel.connect(Gdk.Key.plus, Gdk.ModifierType.CONTROL_MASK,
                        Gtk.AccelFlags.VISIBLE | Gtk.AccelFlags.LOCKED,
                        (group, acceleratable, key, modifier) => {
            web.zoom_level += 0.1;
            return true;
        });
        accel.connect(Gdk.Key.equal, Gdk.ModifierType.CONTROL_MASK,
                        Gtk.AccelFlags.VISIBLE | Gtk.AccelFlags.LOCKED,
                        (group, acceleratable, key, modifier) => {
            // So users can press ctrl-= instead of ctrl-shift-=
            web.zoom_level += 0.1;
            return true;
        });
        accel.connect(Gdk.Key.@0, Gdk.ModifierType.CONTROL_MASK,
                        Gtk.AccelFlags.VISIBLE | Gtk.AccelFlags.LOCKED,
                        (group, acceleratable, key, modifier) => {
            web.zoom_level = 1.0;
            return true;
        });

        add_accel_group(accel);
    }

    private void connect_webview(WebTab tab) {
        var hs = web_event_handlers;

        hs.add(web.load_changed.connect ((load_event) => {
            if (load_event == WebKit.LoadEvent.COMMITTED) {
                back.sensitive = web.can_go_back();
                forward.sensitive = web.can_go_forward();
            } else if (load_event == WebKit.LoadEvent.FINISHED) {
                reload_stop.set_visible_child(reload);
                addressbar.progress_fraction = 0.0;
            } else {
                reload_stop.set_visible_child(stop);
            }
        }));

        bindings.add(web.bind_property("uri", addressbar, "text"));
        bindings.add(web.bind_property("title", this, "title"));
        bindings.add(web.bind_property("estimated-load-progress", addressbar,
                            "progress-fraction"));
        hs.add(web.notify["favicon"].connect((sender, property) => {
            if (web.get_favicon() != null) {
                var fav = surface_to_pixbuf(web.get_favicon());
                addressbar.primary_icon_pixbuf = fav;
            }
        }));

        // Replicate tab state to headerbar
        back.sensitive = web.can_go_back();
        forward.sensitive = web.can_go_forward();
        reload_stop.set_visible_child(web.is_loading ? stop : reload);
        addressbar.progress_fraction = web.estimated_load_progress == 1.0 ?
                0.0 : web.estimated_load_progress;
        addressbar.text = web.uri;
        this.title = web.title;
        if (web.get_favicon() != null) {
            var fav = surface_to_pixbuf(web.get_favicon());
            addressbar.primary_icon_pixbuf = fav;
        } else {
            addressbar.primary_icon_name = "internet-web-browser";
        }
    }

    private void disconnect_webview() {
        foreach (var binding in bindings) {
            binding.unbind();
        }
        bindings.clear();

        foreach (var handler in web_event_handlers) {
            web.disconnect(handler);
        }
        web_event_handlers.clear();
    }
    
    private void find_in_page_cb() {
        var current_tab = (WebTab) tabs.current;
        current_tab.find_in_page();
    }

    private Gtk.Menu build_history_menu(
                List<weak WebKit.BackForwardListItem> items) {
        var menu = new Gtk.Menu();

        items.@foreach((item) => {
            var menuItem = new Gtk.ImageMenuItem.with_label(item.get_title());
            menuItem.activate.connect(() => {
                web.go_to_back_forward_list_item(item);
            });
            favicon_for_menuitem.begin(menuItem, item);
            menuItem.always_show_image = true;

            menu.add(menuItem);
        });
        
        menu.show_all();
        return menu;
    }

    private async void favicon_for_menuitem(Gtk.ImageMenuItem menuitem,
                WebKit.BackForwardListItem item) {
        try {
            var favicon_db = web.web_context.get_favicon_database();
            var favicon = yield favicon_db.get_favicon(item.get_uri(), null);
            var icon = surface_to_pixbuf(favicon);
            menuitem.image = new Gtk.Image.from_gicon(icon, Gtk.IconSize.MENU);
        } catch (Error e) {
            warning("Failed to load favicon for '%s':", item.get_uri());
        }
    }
    
    public void new_tab(string url = "https://ddg.gg/") {
        var tab = new WebTab(tabs, null, url);
        tabs.insert_tab(tab, -1);
        tabs.current = tab;
    }

    // GDK does provide a utility for this,
    // but it requires me to specify size information I do not have.
    public static Gdk.Pixbuf? surface_to_pixbuf(Cairo.Surface surface) {
        try {
            var loader = new Gdk.PixbufLoader.with_mime_type("image/png");
            surface.write_to_png_stream((data) => {
                try {
                    loader.write((uint8[]) data);
                } catch (Error e) {
                    return Cairo.Status.DEVICE_ERROR;
                }
                return Cairo.Status.SUCCESS;
            });
            var pixbuf = loader.get_pixbuf();
            loader.close();
            return pixbuf;
        } catch (Error e) {
            return null;
        }
    }
}