// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/***
    BEGIN LICENSE

    Copyright (C) 2011-2014 elementary Developers

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU Lesser General Public License version 3, as published
    by the Free Software Foundation.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranties of
    MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
    PURPOSE.  See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program.  If not, see <http://www.gnu.org/licenses/>

    END LICENSE
***/
public class PantheonGreeter : Gtk.Window {

    public static LoginGateway login_gateway { get; private set; }

    GtkClutter.Embed clutter;

    Clutter.Actor greeterbox;
    UserListActor userlist_actor;
    UserList userlist;

    TimeLabel time;
    Indicators indicators;
    Wallpaper wallpaper;

    public Settings settings { get; private set; }

    public static PantheonGreeter instance { get; private set; }

    //from this width on we use the shrinked down version
    const int NORMAL_WIDTH = 1200;
    //from this width on the clock wont fit anymore
    const int NO_CLOCK_WIDTH = 920;

    public static bool TEST_MODE { get; private set; }

    private bool natural_scroll;

    public PantheonGreeter () {
        //singleton
        assert (instance == null);
        instance = this;

        TEST_MODE = Environment.get_variable ("LIGHTDM_TO_SERVER_FD") == null;

        if (TEST_MODE) {
            message ("Using dummy LightDM because LIGHTDM_TO_SERVER_FD was not found.");
            login_gateway = new DummyGateway ();
        } else {
            login_gateway = new LightDMGateway ();
        }

        settings = new Settings ("org.pantheon.desktop.greeter");

        natural_scroll = new Settings ("org.gnome.settings-daemon.peripherals.touchpad").get_boolean ("natural-scroll");

        delete_event.connect (() => {
            message ("Window got closed. Exiting...");
            Posix.exit (Posix.EXIT_SUCCESS);
            return false;
        });

        message ("Loading default-avatar...");
        LoginOption.load_default_avatar ();

        message ("Building UI...");
        clutter = new GtkClutter.Embed ();
        greeterbox = new Clutter.Actor ();

        userlist = new UserList (LightDM.UserList.get_instance ());
        userlist_actor = new UserListActor (userlist);

        time = new TimeLabel ();
        if (!TEST_MODE) {
            indicators = new Indicators (settings);
        }
        wallpaper = new Wallpaper ();

        message ("Connecting signals...");
        get_screen ().monitors_changed.connect (monitors_changed);

        login_gateway.login_successful.connect (() => {
            fade_out_ui ();
        });

        configure_event.connect (() => {
            reposition ();
            return false;
        });

        monitors_changed ();

        userlist.current_user_changed.connect ((user) => {
            wallpaper.set_wallpaper (user.background);
            if (!TEST_MODE) {
                indicators.keyboard_menu.user_changed_cb (user);
            }
        });

        /*activate the numlock if needed*/
        var activate_numlock = settings.get_boolean ("activate-numlock");
        if (activate_numlock)
            Granite.Services.System.execute_command ("/usr/bin/numlockx on");

        /*build up UI*/
        clutter.add_events (Gdk.EventMask.BUTTON_RELEASE_MASK);
        var stage = clutter.get_stage () as Clutter.Stage;
        stage.background_color = {0, 0, 0, 255};

        greeterbox.add_child (wallpaper);
        greeterbox.add_child (time);
        greeterbox.add_child (userlist_actor);
        if (!TEST_MODE) {
            greeterbox.add_child (indicators);
        }

        greeterbox.opacity = 0;

        stage.add_child (greeterbox);

        greeterbox.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
        greeterbox.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.HEIGHT, 0));

        if (!TEST_MODE)
            indicators.add_constraint (new Clutter.BindConstraint (greeterbox, Clutter.BindCoordinate.WIDTH, 0));

        clutter.key_press_event.connect (keyboard_navigation);

        add (clutter);
        show_all ();

        scroll_event.connect (scroll_navigation);

        greeterbox.animate (Clutter.AnimationMode.EASE_OUT_QUART, 250, opacity: 255);

        message ("Selecting last used user...");
        var last_user = settings.get_string ("last-user");
        for (var i = 0; i < userlist.size; i++) {
            if (userlist.get_user (i).name == last_user) {
                userlist.current_user = userlist.get_user (i);
                break;
            }
        }
        if (userlist.current_user == null)
            userlist.current_user = userlist.get_user (0);

        message ("Finished building UI...");
        this.get_window ().focus (Gdk.CURRENT_TIME);
    }

    /**
     * Fades out an actor and returns the used transition that we can
     * connect us to its completed-signal.
     */
    Clutter.PropertyTransition fade_out_actor (Clutter.Actor actor) {
        var transition = new Clutter.PropertyTransition ("opacity");
        transition.animatable = actor;
        transition.set_duration (300);
        transition.set_progress_mode (Clutter.AnimationMode.EASE_OUT_CIRC);
        transition.set_from_value (actor.opacity);
        transition.set_to_value (0);
        actor.add_transition ("fadeout", transition);
        return transition;
    }

    /**
     * Fades out the ui and then starts the session.
     * Only call this if the LoginGateway has signaled it is awaiting
     * start_session by firing login_successful!.
     */
    void fade_out_ui () {
        // The animations are always the same. If they would have different
        // lengths we need to use a TransitionGroup to determine
        // the correct time everything is faded out.
        var anim = fade_out_actor (time);
        fade_out_actor (userlist_actor);
        if (!TEST_MODE)
            fade_out_actor (indicators);

        anim.completed.connect (() => {
            login_gateway.start_session ();
        });
    }

    void monitors_changed () {
        Gdk.Rectangle geometry;
        get_screen ().get_monitor_geometry (get_screen ().get_primary_monitor (), out geometry);
        resize (geometry.width, geometry.height);
        move (geometry.x, geometry.y);
        reposition ();
    }

    void reposition () {
        int width = 0;
        int height = 0;

        get_size (out width, out height);

        if (width > NORMAL_WIDTH) {
            userlist_actor.x = 243;
        } else {
            userlist_actor.x = 120 * ((float) (width) / NORMAL_WIDTH);
        }
        userlist_actor.y = Math.floorf (height / 2.0f);

        time.x = width - time.width - 100;
        time.y = height / 2 - time.height / 2;

        time.visible = width > NO_CLOCK_WIDTH;

        wallpaper.width = width;
        wallpaper.screen_width = width;
        wallpaper.height = height;
        wallpaper.screen_height = height;
        wallpaper.reposition ();
    }

    bool keyboard_navigation (Gdk.EventKey e) {
        switch (e.keyval) {
            case Gdk.Key.Num_Lock:
                settings.set_boolean ("activate-numlock", !settings.get_boolean ("activate-numlock"));
                break;
            case Gdk.Key.Up:
                userlist.select_prev_user ();
                break;
            case Gdk.Key.Down:
                userlist.select_next_user ();
                break;
            default:
                return false;
        }

        return true;
    }

    bool scroll_navigation (Gdk.EventScroll e) {
        if (e.device.input_source == Gdk.InputSource.TOUCHPAD && natural_scroll) {
            // Inverse scrolling direction
            switch (e.direction) {
                case Gdk.ScrollDirection.UP:
                    userlist.select_next_user ();
                    break;
                case Gdk.ScrollDirection.DOWN:
                    userlist.select_prev_user ();
                    break;
            }
        } else {
            switch (e.direction) {
                case Gdk.ScrollDirection.UP:
                    userlist.select_prev_user ();
                    break;
                case Gdk.ScrollDirection.DOWN:
                    userlist.select_next_user ();
                    break;
            }
        }

        return false;
    }
}

public static int main (string [] args) {
    message ("Starting pantheon-greeter...");
    /* Protect memory from being paged to disk, as we deal with passwords */
    PosixMLock.mlockall (PosixMLock.MCL_CURRENT | PosixMLock.MCL_FUTURE);

    var init = GtkClutter.init (ref args);
    if (init != Clutter.InitError.SUCCESS)
        error ("Clutter could not be intiailized");


    message ("Applying settings...");
    /*some settings*/
    Intl.setlocale (LocaleCategory.ALL, "");
    Intl.bind_textdomain_codeset ("pantheon-greeter", "UTF-8");
    Intl.textdomain ("pantheon-greeter");

    Gdk.get_default_root_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.LEFT_PTR));

    var settings = Gtk.Settings.get_default ();
    settings.gtk_theme_name = "elementary";
    settings.gtk_icon_theme_name = "elementary";
    settings.gtk_font_name = "Droid Sans";
    settings.gtk_xft_dpi= (int) (1024 * 96);
    settings.gtk_xft_antialias = 1;
    settings.gtk_xft_hintstyle = "hintslight";
    settings.gtk_xft_rgba = "rgb";
    settings.gtk_cursor_blink = true;

    new PantheonGreeter ();
    message ("Entering main-loop...");
    Gtk.main ();
    message ("Gtk.main exited - shutting down.");
    return Posix.EXIT_SUCCESS;
}
