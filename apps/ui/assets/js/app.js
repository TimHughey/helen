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
import { helenWorkLoop } from "./helen";
import "../semantic/dist/semantic";
import "phoenix_html";

// start the Helen periodic work loop
helenWorkLoop();

// $(document).ready(function() {
//   var $headers = $("body > h3"),
//     $header = $headers.first(),
//     ignoreScroll = false,
//     timer;
//
//   // Preserve example in viewport when resizing browser
//   $(window).on("resize", function() {
//     // ignore callbacks from scroll change
//     clearTimeout(timer);
//     $headers.visibility("disable callbacks");
//
//     // preserve position
//     $(document).scrollTop($header.offset().top);
//
//     // allow callbacks in 500ms
//     timer = setTimeout(function() {
//       $headers.visibility("enable callbacks");
//     }, 500);
//   });
//   $headers.visibility({
//     // fire once each time passed
//     once: false,
//
//     // don't refresh position on resize
//     checkOnRefresh: true,
//
//     // lock to this element on resize
//     onTopPassed: function() {
//       $header = $(this);
//     },
//     onTopPassedReverse: function() {
//       $header = $(this);
//     }
//   });
// });
