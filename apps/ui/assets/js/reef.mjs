class Reef {
  constructor(socket) {
    let channel = socket.channel("helen:reef", { data: "initial" });

    channel
      .join()
      .receive("ok", (resp) => {
        // join was a success
        window.channelJoined = true;
      })
      .receive("error", (resp) => {
        console.log("Unable to join", resp);
      });

    channel.on("broadcast", (msg) => {
      this.handleMessage(msg);
    });

    this.channel = channel;
    this.modesLocked = true;
    this.manualControl = false;
  }

  channel() {
    return this.channel;
  }

  clickAction(payload) {
    let { action: action = null } = payload;

    if (action == null) {
      // this was not an action click
      return;
    }

    switch (action) {
      case "unlock-modes":
        if (this.modesLocked) {
          this.modesLock(false);
        } else {
          this.modesLock(true);
          this.pushMessage(payload);
        }
        break;

      case "manual-control":
        this.handleManualControl(payload);
        break;

      case "reset":
      case "stop":
      case "live-update":
        this.pushMessage(payload);
        break;

      default:
        console.log("clickAtion() not implemented: ", payload);
    }
  }

  clickDevice(payload) {
    let { device: device = null } = payload;

    if (device === null || this.manualControl == false) {
      // this was not a device click or manualControl hasn't been actived, do nothing
      return;
    }

    console.log("clickDevice: ", payload);
  }

  clickMode(payload) {
    let { mode: mode = null } = payload;

    if (mode === null) {
      // this was not a step click
      return;
    }

    this.pushMessage(payload);
  }

  handleClick(e) {
    const target = e.currentTarget;
    const channel = this.channel;

    var payload = {
      subsystem: "reef",
      action: jQuery(target).data("action"),
      device: jQuery(target).data("device"),
      mode: jQuery(target).data("mode"),
    };

    // the click functions determine if the payload should be handled
    this.clickDevice(payload);
    this.clickMode(payload);
    this.clickAction(payload);
  }

  handleMessage(msg) {
    console.log("reef status: ", msg);

    const {
      workers: {
        captain: {
          active: {
            mode: captain_mode = null,
            step: captain_step = null,
            action: {
              cmd: captain_cmd = null,
              stmt: captain_stmt = null,
              worker_cmd: captain_worker_cmd = null,
            },
          },
          ready: captain_ready = false,
          status: captain_status = null,
        },
      },
    } = msg;

    this.updateStopButton(captain_mode);

    if (captain_ready == false) {
      this.workerStandbyMode("captain", true);
    } else if (typeof captain_mode == "string") {
      // if the captain mode was specified then update steps
      let steps = this.selectSteps();

      switch (captain_mode) {
        case "all_stop":
        case "none":
          let fill = jQuery(steps).filter("[data-mode='fill']");
          let fill_icon = jQuery(steps).find(".icon");
          let rest = jQuery(steps).filter("[data-mode!='fill']");

          if (this.manualControl == false) {
            this.modeActive(fill);
            this.modeDisabled(rest);
            fill_icon.removeClass("green");
          } else {
            this.modeDisabled(steps);
          }

          break;

        default:
          const active_filter = `[data-mode='${captain_mode}']`;
          const disabled_filter = `[data-mode!='${captain_mode}']`;
          const current_mode = jQuery(steps).filter("a.active");

          const active = jQuery(steps).filter(active_filter);
          const disabled = jQuery(steps).filter(disabled_filter);

          this.modeActive(active);
          this.modeDisabled(disabled);
      }
    }
    this.handleModeStatus(msg);
    this.handleCaptainWorkerStatus(msg);
  }

  handleManualControl(payload) {
    const manual_control = this.manualControl;
    const icon = this.selectButtonIcon("captain", "manual-control");
    const button = jQuery(icon).closest("button");

    // always toggle the manual override flag
    this.manualControl = !manual_control;

    if (this.manualControl) {
      icon.removeClass("radiation").addClass("exclamation");
      button.addClass("active red");
    } else {
      // we are leaving manual control
      icon.removeClass("exclamation").addClass("radiation");
      button.removeClass("active red");
    }

    payload.value = this.manualControl;

    this.pushMessage(payload);
  }

  handleUnlockSteps(msg) {
    if (msg["button_click"] === undefined) {
      return;
    }

    const {
      button_click: { action: action, step: step = "none" },
    } = msg;

    if (action == "unlock-modes") {
      const steps = this.selectSteps();
    } else if (step != "none") {
      this.selectButtonIcon("captain", "unlock-modes").removeClass("open");
    }
  }

  handleModeStatus(msg) {
    const {
      workers: {
        captain: { modes: captain_modes },
        first_mate: { modes: first_mate_modes },
      },
    } = msg;

    const captain_sel = "div[data-subsystem='reef'] .steps";

    for (const { mode: mode_name, status: mode_status } of captain_modes) {
      let step = jQuery(`${captain_sel} a[data-mode="${mode_name}"]`);

      if (step) {
        switch (mode_status) {
          case "running":
            step.addClass("active");
            break;

          case "finished":
            step.removeClass("active").addClass("completed");
            break;

          default:
          // no change to classes
        }
      }
    }
  }

  modeActive(step) {
    const remove = "completed disabled";
    const add = "active";

    jQuery(step).addClass(add).removeClass(remove);

    let icon = jQuery(step).children(".icon");
    icon.addClass("green");
  }

  modeDisabled(step) {
    const remove = "completed active";
    const add = "disabled";

    jQuery(step).removeClass(remove).addClass(add);

    let icon = jQuery(step).children(".icon");
    icon.removeClass("green");
  }

  pageLoaded(page) {
    if (page != this.subsystem()) {
      return;
    }

    const channel = this.channel;

    const reef_buttons = $("[data-subsystem='reef'] .button");
    reef_buttons.on("click", (e) => {
      this.handleClick(e);
    });

    const reef_links = $("div[data-subsystem='reef'] a[data-mode]");
    reef_links.on("click", (e) => {
      this.handleClick(e);
    });

    const live_update = jQuery("#live-update-button");
    live_update.removeClass("disabled");

    live_update.on("click", (e) => {
      this.handleClick(e);
    });

    channel
      .push("page_loaded", { subsystem: "reef" })
      .receive("reef_status", (msg) => {
        this.handleMessage(msg);
      })
      .receive("nop", (msg) => {})
      .receive("error", (reasons) => console.log("error", reasons))
      .receive("timeout", () => console.log("Networking issue..."));
  }

  pushMessage(payload) {
    const channel = this.channel;

    console.log("pushing payload: ", payload);

    channel
      .push("reef_click", payload)
      .receive("reef_status", (msg) => {
        this.handleMessage(msg);
      })
      .receive("nop", (msg) => {})
      .receive("error", (reasons) => console.log("error", reasons))
      .receive("timeout", () => console.log("Networking issue..."));
  }

  selectButton(worker, action) {
    const selector = `div[data-subsystem-worker='${worker}'] button[data-action='${action}']`;

    const button = jQuery(selector);
    return button;
  }

  selectButtonIcon(worker, action) {
    const selector = `div[data-subsystem-worker='${worker}'] button[data-action='${action}'] .icon`;

    const icon = jQuery(selector);

    return icon;
  }

  selectWorkers(subsystem) {
    const selector = `div[data-subsystem-worker='${subsystem}'] div[data-buttons="workers"] .buttons`;

    const buttons = jQuery(selector);

    return buttons;
  }

  selectSteps() {
    return jQuery("div[data-subsystem='reef'] .steps a[data-mode]");
  }

  modesLock(lock) {
    const steps = this.selectSteps();
    const icon = this.selectButtonIcon("captain", "unlock-modes");

    if (lock) {
      // NOTE
      //  updating the disabled class when locking is handled via a
      //  reef status message from the server
      icon.removeClass("open");
      this.modesLocked = true;
    } else {
      // unlocking the steps (remving the disabled class) is handled
      // within the brower and without server interaction
      steps.removeClass("disabled");
      icon.addClass("open");
      this.modesLocked = false;
    }
  }

  subsystem() {
    return "reef";
  }

  handleCaptainWorkerStatus(msg) {
    const {
      workers: {
        captain: { workers: workers },
      },
    } = msg;

    const buttons = this.selectWorkers("captain");
    for (let { status: status, ready: ready, name: name } of workers) {
      const dev_button = jQuery(buttons).find(`[data-worker='${name}']`);

      if (ready && status) {
        dev_button.removeClass("black");
        dev_button.addClass("blue");
      } else if (ready && !status) {
        // device is online and not running
        dev_button.removeClass("blue black");
      } else if (!ready) {
        // device is offline
        dev_button.removeClass("blue");
        dev_button.addClass("black");
      }
    }
  }

  updateStopButton(mode) {
    let stop_button = this.selectButton("captain", "stop");

    switch (mode) {
      case "all_stop":
        stop_button.addClass("red");
        break;

      default:
        stop_button.removeClass("red");
        break;
    }
  }

  workerStandbyMode(worker, standby) {
    switch (worker) {
      case "captain":
        const steps = this.selectSteps();
        steps.removeClass("active green").addClass("disabled");

        const devices = this.selectDevices("captain");
        devices.removeClass("disabled");
    }
  }
}

export { Reef };
