var channel = null;

class Reef {
  constructor(socket) {
    channel = socket.channel("helen:reef", { data: "initial" });

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
      handleMessage(msg);
    });

    this.subsystem = "reef";
    this.channel = channel;
    this.modesLocked = true;
    this.manualControl = false;
  }

  channel() {
    return this.channel;
  }

  pageLoaded(page) {
    if (page != this.subsystem) {
      return;
    }

    const channel = this.channel;

    const reef_buttons = $("[data-subsystem='reef'] .button");
    reef_buttons.on("click", (e) => {
      handleClick(e);
    });

    const reef_links = $("div[data-subsystem='reef'] a[data-mode]");
    reef_links.on("click", (e) => {
      handleClick(e);
    });

    const live_update = jQuery("#live-update-button");
    live_update.removeClass("disabled");

    live_update.on("click", (e) => {
      handleClick(e);
    });

    channel
      .push("page_loaded", { subsystem: "reef" })
      .receive("reef", (msg) => {
        handleMessage(msg);
      })
      .receive("nop", (msg) => {})
      .receive("error", (reasons) => console.log("error", reasons))
      .receive("timeout", () => console.log("Networking issue..."));
  }
}

// function modesLock(worker, lock) {
//   const steps = selectSteps();
//   const icon = selectButtonIcon(worker, "unlock-modes");
//
//   if (lock) {
//     // NOTE
//     //  updating the disabled class when locking is handled via a
//     //  reef status message from the server
//     icon.removeClass("open");
//     this.modesLocked = true;
//   } else {
//     // unlocking the steps (remving the disabled class) is handled
//     // within the brower and without server interaction
//     steps.removeClass("disabled");
//     icon.addClass("open");
//     this.modesLocked = false;
//   }
// }

// function subWorkersStatus(workers, subsystems) {
//   const {
//     captain: {workers: workers}
//   } = subsystems;
//
//   const buttons = this.selectWorkers(worker);
//   for (let {status: status, ready: ready, name: name} of workers) {
//     const dev_button = jQuery(buttons).find(`[data-worker='${name}']`);
//
//     if (ready && status) {
//       dev_button.removeClass("black");
//       dev_button.addClass("blue");
//     } else if (ready && !status) {
//       // device is online and not running
//       dev_button.removeClass("blue black");
//     } else if (!ready) {
//       // device is offline
//       dev_button.removeClass("blue");
//       dev_button.addClass("black");
//     }
//   }
// }

function handleClick(e) {
  const target = e.currentTarget;

  var payload = {
    subsystem: "reef",
    action: jQuery(target).data("action"),
    device: jQuery(target).data("device"),
    mode: jQuery(target).data("mode"),
    worker: workerName(),
  };

  pushMessage(payload);
}

// function handleManualControl(payload) {
//   const manual_control = this.manualControl;
//   const icon = this.selectButtonIcon("captain", "manual-control");
//   const button = jQuery(icon).closest("button");
//
//   // always toggle the manual override flag
//   this.manualControl = !manual_control;
//
//   if (this.manualControl) {
//     icon.removeClass("radiation").addClass("exclamation");
//     button.addClass("active red");
//   } else {
//     // we are leaving manual control
//     icon.removeClass("exclamation").addClass("radiation");
//     button.removeClass("active red");
//   }
//
//   payload.value = this.manualControl;
//
//   this.pushMessage(payload);
// }

// function handleModeStatus(msg) {
//   const {
//     status: {
//       workers: {
//         captain: { modes: captain_modes },
//         first_mate: { modes: first_mate_modes },
//       },
//     },
//   } = msg;
//
//   const captain_sel = "div[data-subsystem='reef'] .steps";
//
//   for (const { mode: mode_name, status: mode_status } of captain_modes) {
//     let step = jQuery(`${captain_sel} a[data-mode="${mode_name}"]`);
//
//     if (step) {
//       switch (mode_status) {
//         case "running":
//           step.addClass("active");
//           break;
//
//         case "finished":
//           step.removeClass("active").addClass("completed");
//           break;
//
//         default:
//         // no change to classes
//       }
//     }
//   }
// }

function handleMessage(msg) {
  console.log("reef message: ", msg);

  const {
    status: { workers: workers = [] },
    ui: ui = {},
  } = msg;

  for (let worker in workers) {
    workerMessage(workers[worker]);
  }

  // updateStopButton(captain_mode);
  //
  // if (captain_ready == false) {
  //   workerStandbyMode("captain", true);
  // } else if (typeof captain_mode == "string") {
  //   // if the captain mode was specified then update steps
  //   let steps = selectSteps();
  //
  //   switch (captain_mode) {
  //     case "all_stop":
  //     case "none":
  //       let fill = jQuery(steps).filter("[data-mode='fill']");
  //       let fill_icon = jQuery(steps).find(".icon");
  //       let rest = jQuery(steps).filter("[data-mode!='fill']");
  //
  //       if (this.manualControl == false) {
  //         this.modeActive(fill);
  //         this.modeDisabled(rest);
  //         fill_icon.removeClass("green");
  //       } else {
  //         this.modeDisabled(steps);
  //       }
  //
  //       break;
  //
  //     default:
  //       const active_filter = `[data-mode='${captain_mode}']`;
  //       const disabled_filter = `[data-mode!='${captain_mode}']`;
  //       const current_mode = jQuery(steps).filter("a.active");
  //
  //       const active = jQuery(steps).filter(active_filter);
  //       const disabled = jQuery(steps).filter(disabled_filter);
  //
  //       this.modeActive(active);
  //       this.modeDisabled(disabled);
  //   }
  // }
  // this.handleModeStatus(msg);
  // this.handleCaptainWorkerStatus(msg);
}

// function handleUnlockSteps(msg) {
//   if (msg["button_click"] === undefined) {
//     return;
//   }
//
//   const {
//     button_click: { action: action, step: step = "none" },
//   } = msg;
//
//   if (action == "unlock-modes") {
//     const steps = this.selectSteps();
//   } else if (step != "none") {
//     this.selectButtonIcon("captain", "unlock-modes").removeClass("open");
//   }
// }

function workerMessage(msg) {
  const {
    name: worker_name,
    active: {
      mode: mode = null,
      step: step = null,
      action: {
        cmd: cmd = null,
        stmt: stmt = null,
        worker_cmd: worker_cmd = null,
      },
    },
    ready: mode_ready = false,
    status: mode_status = null,
    sub_workers: sub_workers,
  } = msg;

  console.log("workerMessage: ", msg);

  updateStopButton(worker_name, mode);
  //
  // if (ready == false) {
  //   standbyMode(subsystem, true);
  // } else if (typeof mode == "string") {
  //   // if the captain mode was specified then update steps
  //   let steps = selectSteps(worker);
  //
  //   switch (mode) {
  //     case "all_stop":
  //     case "none":
  //       let fill = jQuery(steps).filter("[data-mode='fill']");
  //       let fill_icon = jQuery(steps).find(".icon");
  //       let rest = jQuery(steps).filter("[data-mode!='fill']");
  //
  //       modeActive(fill);
  //       modeDisabled(rest);
  //       fill_icon.removeClass("green");
  //
  //       break;
  //
  //     default:
  //       const active_filter = `[data-mode='${captain_mode}']`;
  //       const disabled_filter = `[data-mode!='${captain_mode}']`;
  //       const current_mode = jQuery(steps).filter("a.active");
  //
  //       const active = jQuery(steps).filter(active_filter);
  //       const disabled = jQuery(steps).filter(disabled_filter);
  //
  //       modeActive(active);
  //       modeDisabled(disabled);
  //   }
  // }
  // handleModeStatus(worker, msg);
  // handleCaptainWorkerStatus(worker, msg);
}

// function modeActive(step) {
//   const remove = "completed disabled";
//   const add = "active";
//
//   jQuery(step).addClass(add).removeClass(remove);
//
//   let icon = jQuery(step).children(".icon");
//   icon.addClass("green");
// }

// function modeDisabled(step) {
//   const remove = "completed active";
//   const add = "disabled";
//
//   jQuery(step).removeClass(remove).addClass(add);
//
//   let icon = jQuery(step).children(".icon");
//   icon.removeClass("green");
// }

function pushMessage(payload) {
  console.log("pushing payload: ", payload);

  channel
    .push("reef_click", payload)
    .receive("reef", (msg) => {
      handleMessage(msg);
    })
    .receive("nop", (msg) => {})
    .receive("error", (reasons) => console.log("error", reasons))
    .receive("timeout", () => console.log("Networking issue..."));
}

function selectButton(worker, action) {
  const worker_target = selectWorker(worker);
  const button_target = worker_target.find(`button[data-action='${action}']`);

  return button_target;
}
//
// function selectButtonIcon(worker, action) {
//   const selector = `div[data-subsystem-worker='${worker}'] button[data-action='${action}'] .icon`;
//
//   const icon = jQuery(selector);
//
//   return icon;
// }
//
function selectWorker(worker) {
  const target = jQuery(
    `div[data-subsystem='reef'] div[data-subsystem-worker=${worker}]`
  );

  return target;
}

// function selectSubWorkers(worker) {
//   return selectWorker(worker).find('div[data-buttons="workers"] .buttons');
// }
//
// function selectSteps(worker) {
//   return selectWorker(worker).find(".steps a[data-mode]");
// }
//
function updateStopButton(worker, mode) {
  let stop_button = selectButton(worker, "stop");

  switch (mode) {
    case "all_stop":
    case "none":
      stop_button.addClass("red");
      break;

    default:
      stop_button.removeClass("red");
      break;
  }
}
//
// function workerStandby(worker, standby) {
//   const {}
//   switch (worker) {
//     case "captain":
//       const steps = selectSteps(subsystem);
//       steps.removeClass("active green").addClass("disabled");
//
//       const devices = this.selectDevices("captain");
//       devices.removeClass("disabled");
//   }
// }

function workerName() {
  const target = jQuery(
    "div[data-subsystem='reef'] div[data-subsystem-worker]"
  );
  const worker = target.data("subsystem-worker");

  return worker;
}

export { Reef };
