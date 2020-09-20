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

    channel.on("live_update", (msg) => {
      handleMessage(msg);
    });

    this.subsystem = "reef";
    this.channel = channel;
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

function handleClick(e) {
  const target = e.currentTarget;

  var payload = {
    subsystem: "reef",
    action: jQuery(target).data("action"),
    device: jQuery(target).data("device"),
    mode: jQuery(target).data("mode"),
    worker: jQuery(target)
      .closest("div[data-subsystem-worker]")
      .data("subsystem-worker"),
  };

  pushMessage(payload);
}

function handleMessage(msg) {
  const {
    live_update: live_update = false,
    modes_locked: modes_locked = true,
  } = msg;

  if (live_update == true) {
    // console.log("reef message: ", msg);
  } else {
    console.log("reef message: ", msg);
  }

  const {
    status: { workers: workers = [] },
    ui: ui = {},
  } = msg;

  for (let worker in workers) {
    workerMessage(workers[worker], modes_locked);
  }

  updateUI(ui, live_update);
}

function modeActive(target) {
  const remove = "completed disabled";
  const add = "active";

  jQuery(target).addClass(add).removeClass(remove);

  let icon = jQuery(target).children(".icon");
  icon.removeClass("black").addClass("green").transition("tada");
}

function modeDisabled(target, modes_locked = true) {
  const remove = "completed active";

  jQuery(target).removeClass(remove).toggleClass("disabled", modes_locked);

  let icon = jQuery(target).children(".icon");
  icon.removeClass("green");
}

function modeFinished(target, modes_locked = true) {
  const remove = "active";
  const add = "completed";

  jQuery(target)
    .addClass(add)
    .removeClass(remove)
    .toggleClass("disabled", modes_locked);

  let icon = jQuery(target).children(".icon");
  icon.addClass("green");
}

function modeReady(target) {
  const remove = "active completed disabled";

  jQuery(target).removeClass(remove);

  let icon = jQuery(target).children(".icon");
  icon.addClass("black");
}

function modeUnlocked(target) {
  const remove = "disabled";

  jQuery(target).removeClass(remove);
}

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

function selectButtonIcon(worker, action) {
  const worker_target = selectWorker(worker);
  const button_target = worker_target.find(`button[data-action='${action}']`);
  const icon_target = button_target.find(".icon");

  return icon_target;
}

function selectWorker(worker) {
  const subsystem_target = jQuery("div[data-subsystem='reef']");
  const worker_target = subsystem_target.find(workerSelector(worker));

  return worker_target;
}

function selectStep(targets, mode_name) {
  const step_target = targets.find(`a[data-mode="${mode_name}"]`);

  return step_target;
}

function selectSteps() {
  const subsystem_target = jQuery("div[data-subsystem='reef']");

  const targets = subsystem_target.find(".steps");

  return targets;
}

function selectStepsDisabled() {
  const subsystem_target = jQuery("div[data-subsystem='reef']");

  const targets = subsystem_target.find(".steps .disabled");

  return targets;
}

function selectSubworkers(worker) {
  const worker_target = selectWorker(worker);
  const subworker_targets = worker_target.find('div[data-buttons="workers"]');
  const targets = subworker_targets.find(".buttons");

  return targets;
}

function selectSubWorker(targets, name) {
  const target = jQuery(targets).find(`[data-worker='${name}']`);

  return target;
}

function updateModes(msg, modes_locked = true) {
  const { name: worker_name, modes: modes } = msg;

  const step_targets = selectSteps();

  for (const { mode: mode_name, status: mode_status } of modes) {
    let target = selectStep(step_targets, mode_name);

    if (target) {
      switch (mode_status) {
        case "running":
        case "holding":
          modeActive(target);
          break;

        case "finished":
          modeFinished(target, modes_locked);
          break;

        case "none":
          modeDisabled(target, modes_locked);

        default:
        // no change to classes
      }
    }
  }
}

function updateStopButton(worker, mode) {
  let stop_button = selectButton(worker, "stop");

  switch (mode) {
    case "all_stop":
    case "none":
      stop_button.addClass("purple");
      break;

    default:
      stop_button.removeClass("purple");
      break;
  }
}

function updateSubworkers(worker_name, sub_workers) {
  const buttons = selectSubworkers(worker_name);

  for (let { status: status, ready: ready, name: name } of sub_workers) {
    const target = selectSubWorker(buttons, name);

    if (ready && status) {
      target.removeClass("black");
      target.addClass("blue");
    } else if (ready && !status) {
      // device is online and not running
      target.removeClass("blue black");
    } else if (!ready) {
      // device is offline
      target.removeClass("blue");
      target.addClass("black");
    }
  }
}

function updateUI(msg, live_update) {
  const { worker: worker = "none", modes_locked: modes_locked = true } = msg;

  if (live_update === true) {
    $("#live-update-button").transition("pulse");
  }

  selectButtonIcon(worker, "lock-modes").toggleClass("open", !modes_locked);

  if (modes_locked === false) {
    selectStepsDisabled(worker).toggleClass("disabled", modes_locked);
  }
}

function workerMessage(msg, modes_locked = true) {
  const {
    name: worker_name,
    active: {
      mode: active_mode = "none",
      step: step = null,
      action: {
        cmd: cmd = null,
        stmt: stmt = null,
        worker_cmd: worker_cmd = null,
      },
    },
    first_mode: first_mode,
    ready: worker_ready = false,
    status: worker_status = null,
    sub_workers: sub_workers,
  } = msg;

  // console.log("workerMessage: ", msg);

  updateStopButton(worker_name, active_mode);
  updateSubworkers(worker_name, sub_workers);

  if (worker_name == "captain") {
    updateModes(msg, modes_locked);

    if (active_mode === "none") {
      const step_targets = selectSteps();
      const first_step_target = selectStep(step_targets, first_mode);

      modeDisabled(step_targets);
      modeReady(first_step_target);
    }
  }
}

function workerSelector(worker) {
  const worker_selector = `div[data-subsystem-worker=${worker}]`;
  return worker_selector;
}

export { Reef };
