// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import "../css/app.scss";
// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured
// in "webpack.config.js".
//
// Import deps with the dep name or local files with a relative path, for example:
//
//    import { Socket } from "phoenix"
//
//
// import {Socket} from "phoenix";
// import {socket} from "./socket";
import "../semantic/dist/semantic";
import "phoenix_html";
import { Socket } from "phoenix";
import { Reef } from "./reef";

//
// MAIN CODE
//
// Automatically executed when imported.
//

// establish the websocket
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

var reef = new Reef(socket);

// initialize the dropdown menu
$(".ui.dropdown").dropdown();

// initialize button click callbacks
// let live_update_button = $("#live-update-button");
// live_update_button.on("click", setLiveUpdateButton);

// handle page load events
jQuery("document").ready(function () {
  let active_page = jQuery(this).find("div[data-subsystem]").data("subsystem");

  console.log("document ready", active_page);

  reef.pageLoaded(active_page);
});
