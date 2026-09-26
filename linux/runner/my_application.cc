#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Hollow Court");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Hollow Court");
  }

  gtk_window_set_default_size(window, 1280, 720);

  // The window's icon. The Flutter Linux runner does not set one, so without this the window and
  // its entry in a dock or taskbar carry GTK's placeholder -- which is what a reader means when
  // they say the icon is still the system default.
  //
  // The path is derived from the executable rather than from an installed location, because a
  // Flutter Linux bundle is relocatable and an AppImage mounts itself somewhere temporary: the
  // installed icon under /usr/share/icons is a different copy, for the desktop menu, and this
  // program cannot assume it is there. `data/flutter_assets` sits beside the executable in a plain
  // build and in an AppImage alike, so that is where this looks.
  {
    g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
    if (exe != nullptr) {
      g_autofree gchar* dir = g_path_get_dirname(exe);
      g_autofree gchar* icon = g_build_filename(
          dir, "data", "flutter_assets", "assets", "icon", "hollow-court.png", nullptr);
      // The error is REPORTED rather than dropped. The first version passed nullptr and a missing
      // file or a gdk-pixbuf that could not read the PNG failed in complete silence: the window
      // simply came up with the placeholder, with nothing anywhere saying why. A one-line warning
      // on stderr is the difference between a bug somebody can find and a bug that is invisible.
      g_autoptr(GError) icon_error = nullptr;
      if (!gtk_window_set_icon_from_file(window, icon, &icon_error)) {
        g_warning("could not load the window icon from %s: %s", icon,
                  icon_error != nullptr ? icon_error->message : "unknown error");
      }
      // And the same file as the default for every window this process opens. Both calls are here
      // because they do different jobs and the difference is not obvious: the per-window call sets
      // this window's icon, while the default applies to windows GTK realizes later -- including
      // the transient ones a file chooser or a dialog brings with it, which would otherwise come up
      // with the placeholder even when the main window looks right.
      gtk_window_set_default_icon_from_file(icon, nullptr);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // The program name, which is NOT the application id, and the two are deliberately different.
  //
  // `g_set_prgname` is what GTK and the desktop environment use to map this running application to
  // its `.desktop` file, so it has to be the dotless name those files are built around -- see the
  // note in `linux/CMakeLists.txt`, where WSLg's key derivation makes a dotted name unmatchable.
  //
  // The application id immediately below must be the opposite: GLib's `g_application_id_is_valid`
  // requires a dot, and passing this name there produced
  // `GLib-GIO-CRITICAL: g_application_set_application_id: assertion ... failed` on every launch.
  // One string was doing both jobs until 2026-09-21, and it could not do both.
  g_set_prgname(PRGNAME);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
