class Reef {
  constructor(channel) {
    this.channel = channel;
    this.stepsLocked = true;
    this.manualControl = false;
  }

  // allStop(steps) {
  //   for (const step of steps) {
  //     // when the captain is answering all stop then only Fill is available
  //     switch ($(step).data("step")) {
  //       case "fill":
  //         $(step).removeClass("active disabled completed");
  //         break;
  //
  //       default:
  //         $(step).removeClass("active completed").addClass("disabled");
  //     }
  //   }
  // }

  channel() {
    return this.channel;
  }

  clickAction(payload) {
    let {action: action = null} = payload;

    if (action == null) {
      // this was not an action click
      return;
    }

    switch (action) {
      case "unlock-steps":
        if (this.stepsLocked) {
          this.stepsLock(false);
        } else {
          this.stepsLock(true);
          this.pushMessage(payload);
        }
        break;

      case "manual-control":
        this.handleManualControl(payload);
        break;

      default:
        console.log("handleActionClick() not implemented: ", payload);
    }
  }

  clickDevice(payload) {
    let {device: device = null} = payload;

    if (device === null || this.manualControl == false) {
      // this was not a device click or manualControl hasn't been actived, do nothing
      return;
    }

    console.log("clickDevice: ", payload);
  }

  clickStep(payload) {
    let {step: step = null} = payload;

    if (step === null) {
      // this was not a step click
      return;
    }

    this.pushMessage(payload);
  }

  handleClick(e) {
    const target = e.currentTarget;
    const channel = this.channel;

    console.log("reef click: ", target);

    var payload = {
      subsystem: "reef",
      action: jQuery(target).data("action"),
      device: jQuery(target).data("device"),
      step: jQuery(target).data("step")
    };

    // the click functions determine if the payload should be handled
    this.clickDevice(payload);
    this.clickStep(payload);
    this.clickAction(payload);
  }

  handleMessage(msg) {
    console.log("reef status: ", msg);

    const {
      workers: {
        captain: {
          mode: captain_mode = null,
          devices: captain_devices = [],
          active: captain_active = false
        }
      }
    } = msg;

    if (captain_active == false) {
      this.workerStandbyMode("captain", true);
    } else if (typeof captain_mode == "string") {
      // if the captain mode was specified then update steps
      let steps = this.selectSteps();

      switch (captain_mode) {
        case "all_stop":
        case "ready":
          let fill = jQuery(steps).filter("[data-step='fill']");
          let fill_icon = jQuery(steps).find(".icon");
          let rest = jQuery(steps).filter("[data-step!='fill']");

          if (this.manualControl == false) {
            this.modeActive(fill);
            this.modeDisabled(rest);
            fill_icon.removeClass("green");
          } else {
            this.modeDisabled(steps);
          }

          break;

        default:
          const active_filter = `[data-step='${captain_mode}']`;
          const disabled_filter = `[data-step!='${captain_mode}']`;
          const current_step = jQuery(steps).filter("a.active");

          const active = jQuery(steps).filter(active_filter);
          const disabled = jQuery(steps).filter(disabled_filter);

          this.modeActive(active);
          this.modeDisabled(disabled);
      }
    }
    this.handleStepStatus(msg);
    this.updateDevices("captain", captain_devices);
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
      button_click: {action: action, step: step = "none"}
    } = msg;

    if (action == "unlock-steps") {
      const steps = this.selectSteps();
    } else if (step != "none") {
      this.selectButtonIcon("captain", "unlock-steps").removeClass("open");
    }
  }

  handleStepStatus(msg) {
    const {
      workers: {
        captain: {steps: captain_steps},
        first_mate: {steps: first_mate_steps}
      }
    } = msg;

    const captain_sel = "div[data-subsystem='reef'] .steps";

    for (const {step: step_name, status: step_status} of captain_steps) {
      let step = jQuery(`${captain_sel} a[data-step="${step_name}"]`);

      if (step) {
        switch (step_status) {
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

    jQuery(step)
      .addClass(add)
      .removeClass(remove);

    let icon = jQuery(step).children(".icon");
    icon.addClass("green");
  }

  modeDisabled(step) {
    const remove = "completed active";
    const add = "disabled";

    jQuery(step)
      .removeClass(remove)
      .addClass(add);

    let icon = jQuery(step).children(".icon");
    icon.removeClass("green");
  }

  pageLoaded(page) {
    if (page != this.subsystem()) {
      return;
    }

    const channel = this.channel;

    const reef_buttons = $("[data-subsystem='reef'] .button");
    reef_buttons.on("click", e => {
      this.handleClick(e);
    });

    const reef_links = $("div[data-subsystem='reef'] a[data-step]");
    reef_links.on("click", e => {
      this.handleClick(e);
    });

    jQuery("#live-update-button").removeClass("disabled");

    channel
      .push("page_loaded", {subsystem: "reef"})
      .receive("reef_status", msg => {
        this.handleMessage(msg);
      })
      .receive("nop", msg => {})
      .receive("error", reasons => console.log("error", reasons))
      .receive("timeout", () => console.log("Networking issue..."));
  }

  pushMessage(payload) {
    const channel = this.channel;

    channel
      .push("reef_click", payload)
      .receive("reef_status", msg => {
        this.handleMessage(msg);
      })
      .receive("nop", msg => {})
      .receive("error", reasons => console.log("error", reasons))
      .receive("timeout", () => console.log("Networking issue..."));
  }

  selectButtonIcon(worker, action) {
    const selector = `div[data-subsystem-worker='${worker}'] button[data-action='${action}'] .icon`;

    const icon = jQuery(selector);

    return icon;
  }

  selectDevices(worker) {
    const selector = `div[data-subsystem-worker='${worker}'] div[data-buttons="devices"] .buttons`;

    const buttons = jQuery(selector);

    return buttons;
  }

  selectSteps() {
    return jQuery("div[data-subsystem='reef'] .steps a[data-step]");
  }

  stepsLock(lock) {
    const steps = this.selectSteps();
    const icon = this.selectButtonIcon("captain", "unlock-steps");

    if (lock) {
      // NOTE
      //  updating the disabled class when locking is handled via a
      //  reef status message from the server
      icon.removeClass("open");
      this.stepsLocked = true;
    } else {
      // unlocking the steps (remving the disabled class) is handled
      // within the brower and without server interaction
      steps.removeClass("disabled");
      icon.addClass("open");
      this.stepsLocked = false;
    }
  }

  subsystem() {
    return "reef";
  }

  updateDevices(worker, devices_status) {
    const buttons = this.selectDevices(worker);
    for (let {online: online, active: active, name: name} of devices_status) {
      const dev_button = jQuery(buttons).find(`[data-device='${name}']`);

      if (online && active) {
        dev_button.removeClass("black");
        dev_button.addClass("blue");
      } else if (online && !active) {
        // device is online and not running
        dev_button.removeClass("blue black");
      } else if (!online) {
        // device is offline
        dev_button.removeClass("blue");
        dev_button.addClass("black");
      }
    }
  }

  workerStandbyMode(worker, standby) {
    switch (worker) {
      case "captain":
        const steps = this.selectSteps();
        steps.removeClass("active green").addClass("disabled");

        const devices = this.selectDevices();
        devices.removeClass("disabled");
    }
  }
}

export {Reef};
