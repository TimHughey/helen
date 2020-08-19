class Roost {
  constructor(channel) {
    this.channel = channel;

    let roost_buttons = $("button[data-subsystem='roost']");
    roost_buttons.on("click", this.handleClick);
  }

  handleClick(e) {
    let payload = {
      subsystem: "roost",
      mode: $(target)
        .closest("div.card")
        .data("mode"),
      action: $(target).data("action")
    };

    if (this.channel.canPush()) {
      push("roost_click", payload);
    }
  }

  handleMessage(msg) {
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
}

export {Roost};
