var channel = null;

class Roost {
  constructor(socket) {
    channel = socket.channel("helen:roost", {data: "initial"});

    channel
      .join()
      .receive("ok", resp => {
        // join was a success
        window.channelJoined = true;
      })
      .receive("error", resp => {
        console.log("Unable to join", resp);
      });

    channel.on("live_update", msg => {
      handleMessage(msg);
    });

    this.subsystem = "roost";
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

    const roost_buttons = $("[data-subsystem='roost'] .button");
    roost_buttons.on("click", e => {
      handleClick(e);
    });

    const roost_links = $("div[data-subsystem='roost'] a[data-mode]");
    roost_links.on("click", e => {
      handleClick(e);
    });

    const live_update = jQuery("#live-update-button");
    live_update.removeClass("disabled");

    live_update.on("click", e => {
      handleClick(e);
    });

    channel
      .push("page_loaded", {subsystem: "roost"})
      .receive("roost", msg => {
        handleMessage(msg);
      })
      .receive("nop", msg => {})
      .receive("error", reasons => console.log("error", reasons))
      .receive("timeout", () => console.log("Networking issue..."));
  }
}

function captialize(string) {
  return string.charAt(0).toUpperCase() + string.slice(1);
}

function handleClick(e) {
  const target = e.currentTarget;

  var payload = {
    subsystem: jQuery(target)
      .closest("[data-subsystem]")
      .data("subsystem"),
    action: jQuery(target)
      .closest("[data-action]")
      .data("action"),
    mode: jQuery(target)
      .closest("[data-mode]")
      .data("mode"),
    worker: jQuery(target)
      .closest("[data-worker]")
      .data("worker")
  };

  pushMessage(payload);
}

function handleMessage(msg) {
  const {live_update: live_update = false} = msg;

  if (live_update == true) {
    // nothing
  } else {
    console.log("roost message: ", msg);
  }

  const {
    status: {workers: workers = []},
    ui: ui = {}
  } = msg;

  for (let worker in workers) {
    workerMessage(workers[worker]);
  }
}

function modeStatus(target, text) {
  const mode_color = {
    Finished: "grey",
    Holding: "blue",
    Ready: "green",
    Running: "red"
  };

  target.text(text);

  for (const status in mode_color) {
    if (status === text) {
      target.addClass(mode_color[status]);
    } else {
      target.removeClass(mode_color[status]);
    }
  }
}

function pushMessage(payload) {
  console.log("pushing payload: ", payload);

  channel
    .push("roost_click", payload)
    .receive("roost", msg => {
      handleMessage(msg);
    })
    .receive("nop", msg => {})
    .receive("error", reasons => console.log("error", reasons))
    .receive("timeout", () => console.log("Networking issue..."));
}

function selectButton(worker, mode, action) {
  const target = selectMode(worker, mode).find(`button[data-action=${action}]`);

  return target;
}

function selectButtonIcon(worker, mode, action) {
  const button_target = selectButton(worker, mode, action);
  const target = button_target.find(".icon");

  return target;
}

function selectMode(worker, mode) {
  return selectWorker(worker).find(`[data-mode=${mode}]`);
}

function selectModeStatus(worker, mode) {
  const worker_target = selectWorker(worker);
  const mode_target = worker_target.find(`[data-mode=${mode}]`);
  const target = mode_target.find(".label [data-status]");

  return target;
}

function selectWorker(worker) {
  const subsystem_target = jQuery("div[data-subsystem]");
  const target = subsystem_target.find(`div[data-worker='${worker}']`);

  return target;
}

function updateModes(msg) {
  const {name: worker_name, modes: modes} = msg;

  for (const {mode: mode_name, status: mode_status} of modes) {
    const status_target = selectModeStatus(worker_name, mode_name);
    const stop_button = selectButton(worker_name, mode_name, "stop");
    const play_button = selectButton(worker_name, mode_name, "play");

    if (status_target === undefined || stop_button === undefined) {
      continue;
    }

    const mode_text =
      mode_status === "none" ? "Ready" : captialize(mode_status);
    modeStatus(status_target, mode_text);

    switch (mode_status) {
      case "running":
      case "holding":
        play_button.addClass("red");
        stop_button.removeClass("purple");
        break;

      default:
        play_button.removeClass("red");
        stop_button.addClass("purple");
    }
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
        worker_cmd: worker_cmd = null
      }
    },
    first_mode: first_mode,
    ready: worker_ready = false,
    status: worker_status = null,
    sub_workers: sub_workers
  } = msg;

  console.log("roost worker message: ", msg);

  updateModes(msg);
}

export {Roost};
