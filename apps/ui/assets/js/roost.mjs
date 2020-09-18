var channel = null;

class Roost {
  constructor(socket) {
    channel = socket.channel("helen:roost", { data: "initial" });

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
    roost_buttons.on("click", (e) => {
      handleClick(e);
    });

    const roost_links = $("div[data-subsystem='roost'] a[data-mode]");
    roost_links.on("click", (e) => {
      handleClick(e);
    });

    const live_update = jQuery("#live-update-button");
    live_update.removeClass("disabled");

    live_update.on("click", (e) => {
      handleClick(e);
    });

    channel
      .push("page_loaded", { subsystem: "roost" })
      .receive("roost", (msg) => {
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
    subsystem: "roost",
    action: jQuery(target).data("action"),
    device: jQuery(target).data("device"),
    mode: jQuery(target).data("mode"),
    worker: workerName(),
  };

  pushMessage(payload);
}

function handleMessage(msg) {
  const { live_update: live_update = false } = msg;

  if (live_update == true) {
    // nothing
  } else {
    console.log("roost message: ", msg);
  }

  const {
    status: { workers: workers = [] },
    ui: ui = {},
  } = msg;
}

function pushMessage(payload) {
  console.log("pushing payload: ", payload);

  channel
    .push("roost_click", payload)
    .receive("roost", (msg) => {
      handleMessage(msg);
    })
    .receive("nop", (msg) => {})
    .receive("error", (reasons) => console.log("error", reasons))
    .receive("timeout", () => console.log("Networking issue..."));
}

function workerName() {
  return "roost";
}

export { Roost };
