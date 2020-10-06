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

    statePut({ live_update: true });
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

    let state = stateGet();

    state.live_update_interval_id = setInterval(() => {
      if (isLiveUpdateActive()) {
        $("#live-update-button").transition("pulse");
      }
    }, 5000);

    statePut(state);

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

function activeModeUI(worker_name) {
  const target = selectModes(worker_name).filter(".active");

  return target.length === 0 ? "none" : jQuery(target).data("mode");
}

function handleClick(e) {
  const target = e.currentTarget;

  var payload = {
    subsystem: "reef",
    action: jQuery(target).data("action"),
    subworker: jQuery(target).data("subworker"),
    mode: jQuery(target).data("mode"),
    worker: jQuery(target)
      .closest("div[data-subsystem-worker]")
      .data("subsystem-worker"),
  };

  if (payload.action === "live-update") {
    let state = stateGet();
    state.live_update = !state.live_update;
    statePut(state);
  }

  pushMessage(payload);
}

function handleMessage(msg) {
  const { live_update: msg_live_update = false } = msg;

  if (msg_live_update == true && isLiveUpdateActive() == false) {
    return;
  } else if (msg_live_update == true && isLiveUpdateActive()) {
    // console.log("reef message: ", msg);
  } else {
    console.log("reef message: ", msg);

    let state = stateGet();
    console.log("state: ", state);
  }

  const {
    status: { workers: workers = [] },
    ui: ui_msg = {},
  } = msg;

  for (let worker in workers) {
    workerMessage(workers[worker]);
  }

  updateUI(ui_msg);
}

function isLiveUpdateActive() {
  return stateGet("live_update");
}

function modeActive(target) {
  const remove = "completed";
  const add = "active";

  jQuery(target).addClass(add).removeClass(remove);

  let icon = jQuery(target).children(".icon");
  icon.removeClass("black").addClass("green");
}

function modeInactive(target) {
  const remove = "active completed";

  jQuery(target).removeClass(remove);

  let icon = jQuery(target).children(".icon");
  icon.removeClass("green");
}

function modeFinished(target) {
  const remove = "active";
  const add = "completed";

  jQuery(target).addClass(add).removeClass(remove);

  let icon = jQuery(target).children(".icon");
  icon.addClass("green");
}

function modeReady(target) {
  const remove = "active completed";

  jQuery(target).removeClass(remove);

  let icon = jQuery(target).children(".icon");
  icon.addClass("black");
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

function selectMode(worker_name, mode_name) {
  const select = `[data-mode="${mode_name}"]`;
  const target = selectWorker(worker_name).find(select);

  return target;
}

function selectModes(worker_name) {
  const targets = selectWorker(worker_name).find("[data-mode]");

  return targets;
}

function selectModeProgressBar(worker_name, mode) {
  const mode_status = selectWorker(worker_name).find("[data-mode-status]");
  const target = jQuery(mode_status).find(`[data-mode-progress="${mode}"]`);

  return target;
}

function selectSubworkers(worker) {
  const worker_target = selectWorker(worker);
  const subworker_targets = worker_target.find("div[data-subworkers]");
  const targets = subworker_targets.find(".button");

  return targets;
}

function selectSubWorker(targets, name) {
  const target = jQuery(targets).filter(`button[data-subworker="${name}"]`);

  return target;
}

function stateGet(key = "all") {
  const state = JSON.parse(sessionStorage.getItem("reef-state"));

  return key == "all" ? state : state[key];
}

function statePut(state) {
  sessionStorage.setItem("reef-state", JSON.stringify(state));
}

function updateModes(msg) {
  const { name: worker_name, modes: modes } = msg;

  for (const { mode: mode_name, status: mode_status } of modes) {
    const target = selectMode(worker_name, mode_name);

    // skip modes not represented in the user interface
    if (target === undefined) {
      continue;
    }

    if (target) {
      switch (mode_status) {
        case "running":
        case "holding":
          modeActive(target);
          break;

        case "finished":
          modeFinished(target);
          break;

        case "none":
          modeInactive(target);
          break;

        default:
          console.log(
            `updateModes unhandled mode ${mode_name} status: ${mode_status}`
          );
        // no change to classes
      }
    }
  }
}

function updateModeProgress(msg) {
  let {
    name: worker_name,
    active: {
      mode: active_mode = "none",
      action: {
        cmd: cmd = null,
        worker_cmd: worker_cmd = null,
        run_for: { ms: run_for_ms = 0, binary: run_for_binary } = {},
        elapsed: { ms: elapsed_ms = 0 } = {},
      },
    },
  } = msg;

  const progress = selectModeProgressBar(worker_name, active_mode);
  const label = jQuery(progress).find(".label");

  if (run_for_ms === 0) {
    elapsed_ms = 0;
  }

  jQuery(progress).progress({ total: run_for_ms, value: elapsed_ms });

  jQuery(progress).addClass("active");

  let label_html = `${cmd} ${run_for_binary}`;

  jQuery(label).html(label_html);
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
      target.addClass("teal");
    } else if (ready && !status) {
      // device is online and not running
      target.removeClass("teal black");
    } else if (!ready) {
      // device is offline
      target.removeClass("teal");
      target.addClass("black");
    }
  }
}

function updateUI(msg) {
  const { worker: worker = "none" } = msg;

  if (isLiveUpdateActive() === true) {
  }
}

function workerMessage(msg) {
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

  const origin = window.location.origin;
  const uri = "reef/mode/status";
  const status_target = selectWorker(worker_name).find("div[data-mode-status]");
  const progress_target = selectModeProgressBar(worker_name, active_mode);

  const params = jQuery.param({
    active_mode: active_mode,
    worker: worker_name,
  });

  if (progress_target.length === 0) {
    jQuery(status_target).load(uri, params);
  }

  updateStopButton(worker_name, active_mode);
  updateSubworkers(worker_name, sub_workers);

  updateModes(msg);

  if (worker_name === "captain") {
    const base_modes = ["all_stop", "none"];

    if (base_modes.includes(active_mode)) {
      const first_mode_target = selectMode(worker_name, first_mode);

      modeReady(first_mode_target);
    }

    updateModeProgress(msg);
  }
}

function workerSelector(worker) {
  const worker_selector = `div[data-subsystem-worker=${worker}]`;
  return worker_selector;
}

export { Reef };
