import { Socket } from "phoenix";

// MAIN CODE

let socket = new Socket("/socket", {
  params: {
    token: window.userToken,
  },
});

socket.connect();

let channel = socket.channel("helen:admin", { data: "initial" });
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
  console.log("Message: ", msg);
});

function loop() {
  if (window.autoRefresh) {
    push("refresh_page", { active_page: window.activePage });
  }

  setTimeout(loop, 1000);
}

function helenWorkLoop() {
  document.addEventListener("DOMContentLoaded", (event) => {
    console.log("DOMContentLoaded: ", event);

    setTimeout(() => {
      loop();
    }, 1000);
  });
}

function push(msg, payload) {
  channel
    .push(msg, payload, 10000)
    .receive("refresh_section", (msg) => {
      document.getElementById(msg.section).innerHTML = msg.html;
    })
    .receive("nop", (msg) => {})
    .receive("error", (reasons) => console.log("error", reasons))
    .receive("timeout", () => console.log("Networking issue..."));
}

document.body.addEventListener("click", function (e) {
  if (e.target.id == "auto_refresh") {
    window.autoRefresh = !window.autoRefresh;

    let refreshButton = document.getElementById("auto_refresh");

    if (window.autoRefresh) {
      refreshButton.className = "auto-refresh-active";
    } else {
      refreshButton.className = "auto-refresh-inactive";
    }
  } else if (e.target.tagName == "BUTTON") {
    push("button_click", {
      active_page: window.activePage,
      child: e.target.firstChild.data,
      class: e.target.className,
      value: e.target.value,
      id: e.target.id,
    });
  } else {
    console.log("click: ", e);
  }
});

export { helenWorkLoop };
