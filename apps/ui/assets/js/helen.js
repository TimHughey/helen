import {Socket} from "phoenix";

//
// Functions
//

function logClick(e) {
  console.log("catchall: ", e, e.target);
}

function helenWorkLoop() {
  $("document").ready(function() {
    console.log("document ready, active page: ", window.activePage);

    let active_page = window.activePage;

    let live_update_button = $("#live-update-button");

    switch (active_page) {
      case "home":
      case "module_config":
        live_update_button.addClass("disabled");
        break;

      case "roost":
      case "reef":
        live_update_button.removeClass("disabled");
        break;

      default:
        live_update_button.addClass("disabled");
        break;
    }

    push("page_loaded", {active_page: active_page});

    setTimeout(() => {
      loop();
    }, 1000);
  });
}

function loop() {
  if (window.liveUpdate) {
    push("refresh_page", {active_page: window.activePage});
  }

  setTimeout(loop, 1000);
}

function moduleConfigOptions(msg) {
  let textarea = $("#textarea-module-config");
  textarea.val(msg.opts);

  textarea.attr("data-mod-str", msg.mod_str);

  let field = $("#field-module-config");
  field.removeClass("disabled");
}

function push(msg, payload) {
  channel
    .push(msg, payload, 10000)
    .receive("home_status", msg => {})
    .receive("reef_status", reefStatus)
    .receive("roost_status", roostStatus)
    .receive("module_config", moduleConfigOptions)
    .receive("nop", msg => {})
    .receive("error", reasons => console.log("error", reasons))
    .receive("timeout", () => console.log("Networking issue..."));
}

function setCaptainDeviceStatus(dev, status) {
  if (status.active) {
    if (status.position) {
      dev.removeClass("green blue pink");
      dev.addClass("red");
    } else {
      dev.removeClass("red green blue pink");
    }
  } else {
    dev.removeClass("red green blue pink");
    dev.addClass("black");
  }
}

function setLiveUpdateButton(e) {
  window.liveUpdate = !window.liveUpdate;

  if (window.liveUpdate) {
    $(this).addClass("green");
  } else {
    $(this).removeClass("green");
  }
}

function reefStatus(msg) {
  function queryButton(dev_name) {
    let selector = `#reef-captain-${dev_name}`;

    return $(selector);
  }

  let dev_names = [""];

  let reset = queryButton("reset");
  let all_stop = queryButton("all-stop");
  let pump = queryButton("water-pump");
  let air = queryButton("air-pump");
  let rodi = queryButton("rodi-valve");
  let heater = queryButton("heater");

  var all_devices = [pump, air, rodi, heater];

  switch (msg.captain.step) {
    case "all_stop":
      for (const dev of all_devices) {
        dev.removeClass("red green blue");
      }

      all_stop.addClass("pink");
      break;
  }

  let captain = msg.captain;
  let steps = msg.captain.steps;

  setCaptainDeviceStatus(pump, captain.pump);
  setCaptainDeviceStatus(air, captain.air);
  setCaptainDeviceStatus(rodi, captain.rodi);
  setCaptainDeviceStatus(heater, captain.heater);

  // console.log("reef status: ", msg);
}

function roostClick(e) {
  let button = e.currentTarget;
  let mode = $(button)
    .closest("div.card")
    .data("mode");
  let action = $(button).data("action");

  let payload = {subsystem: "roost", mode: mode, action: action};

  push("roost_click", payload);
}

function roostStatus(msg) {
  for (const mode_status of msg.modes) {
    let mode = mode_status.mode;

    let click = msg["button_click"];

    if (click && click["rc"] == "answering_all_stop") {
      var status = "stop";
    } else {
      var status = mode_status.status;
    }

    let card_selector = `[data-mode='${mode}']`;
    let active_button_selector = `button[data-action='${status}']`;
    let inactive_button_selector = `button[data-action!='${status}']`;

    let active_mode_button = $(
      `[data-subsystem='roost'] ${card_selector} ${active_button_selector}`
    );

    let inactive_mode_buttons = $(
      `[data-subsystem='roost'] ${card_selector} ${inactive_button_selector}`
    );

    active_mode_button.addClass("primary");
    inactive_mode_buttons.removeClass("primary");
  }
}

//
// MAIN CODE
//
// Automatically executed when imported.
//
let socket = new Socket("/socket", {
  params: {
    token: window.userToken
  }
});

socket.connect();

// initialize the dropdown menu
$(".ui.dropdown").dropdown();

// initialize button click callbacks
let live_update_button = $("#live-update-button");
live_update_button.on("click", setLiveUpdateButton);

let mod_config_menu = $("#menu-module-config a");
mod_config_menu.on("click", function(e) {
  let mod = e.target.attributes.getNamedItem("data-mod").value;

  push("module_config_selection", {
    active_page: window.activePage,
    mod_str: mod
  });
});

let reef_captain_buttons = $("button[id*='reef-captain']");
reef_captain_buttons.on("click", function(e) {
  let id = e.currentTarget.id;

  console.log("reef captain click: ", e);
  console.log("reef captain button id: ", id);
});

let reef_captain_steps = $("a[id*='reef-captain-step']");
reef_captain_steps.on("click", function(e) {
  let id = e.currentTarget.id;

  console.log("reef captain step click: ", e);
  console.log("reef captain step id: ", id);
});

let roost_buttons = $("[data-subsystem='roost'] .button");
roost_buttons.on("click", roostClick);

let channel = socket.channel("helen:admin", {data: "initial"});
channel
  .join()
  .receive("ok", resp => {
    // join was a success
    window.channelJoined = true;
  })
  .receive("error", resp => {
    console.log("Unable to join", resp);
  });

channel.on("broadcast", msg => {
  console.log("Message: ", msg);
});

// let all_elements = $("*");
//
// all_elements.on("click", clickCatchAll);

// document.body.addEventListener("click", function(e) {
// if (e.target.tagName == "BUTTON") {
//   let payload = {
//     active_page: window.activePage,
//     child: e.target.firstChild.data,
//     class: e.target.className,
//     value: e.target.value,
//     id: e.target.id,
//   };
//
//   push("button_click", payload);
// } else {
// console.log("catchall: ", e, e.target);
// console.log("click target: ", e.target);
// }
// });

export {helenWorkLoop};
