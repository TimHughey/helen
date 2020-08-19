class ModuleConfigOptions {
  constructor(channel) {
    this.channel = channel;
  }

  clickModule(payload) {
    this.pushMessage(payload);
  }

  handleClick(e) {
    const target = e.currentTarget;
    const channel = this.channel;

    console.log("module-config click: ", target);

    var payload = {
      subsystem: "module-config",
      module: jQuery(target).data("mod")
    };

    this.clickModule(payload);
  }

  handleInput(e) {
    console.log("module-config input: ", e);
  }

  handleKey(e) {
    if (e.originalEvent != undefined && e.originalEvent.code == "Tab") {
      e.preventDefault();
    }
  }

  handleMessage(msg) {
    console.log("module config msg: ", msg);

    const {opts: opts, module: module} = msg;

    const textarea = jQuery("textarea[data-input='module_config']");

    console.log("module config textarea: ", textarea);

    textarea.val(opts);
  }

  pageLoaded(page) {
    if (page != this.subsystem()) {
      return;
    }

    const channel = this.channel;

    const a_links = jQuery("[data-subsystem='module-config'] a[data-mod]");
    a_links.on("click", e => {
      this.handleClick(e);
    });

    const input = jQuery("textarea[data-input='module_config']");
    console.log("module_config select textarea", input);
    input.on("input", e => this.handleInput(e));

    input.on("keydown", e => this.handleKey(e));
  }

  pushMessage(payload) {
    const channel = this.channel;

    channel
      .push("module_config_click", payload)
      .receive("module_config_click_reply", msg => {
        this.handleMessage(msg);
      })
      .receive("nop", msg => {})
      .receive("error", reasons => console.log("error", reasons))
      .receive("timeout", () => console.log("Networking issue..."));
  }

  subsystem() {
    return "module-config";
  }
}

export {ModuleConfigOptions};
