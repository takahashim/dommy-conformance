// The app's Stimulus controllers, the kind a Rails app's app/javascript/
// controllers holds.
(() => {
  const app = Stimulus.Application.start();

  app.register("counter", class extends Stimulus.Controller {
    static targets = ["count"];
    connect() { this.n = 0; }
    increment() { this.countTarget.textContent = String(++this.n); }
  });

  app.register("toggle", class extends Stimulus.Controller {
    static targets = ["panel"];
    toggle() { this.panelTarget.hidden = !this.panelTarget.hidden; }
  });

  app.register("filter", class extends Stimulus.Controller {
    static targets = ["input", "item"];
    filter() {
      const q = this.inputTarget.value;
      for (const li of this.itemTargets) li.hidden = !li.textContent.includes(q);
    }
  });

  app.register("loader", class extends Stimulus.Controller {
    static targets = ["list"];
    async load() {
      const items = await (await fetch("/api/items.json")).json();
      this.listTarget.innerHTML = items.map((i) => `<li>${i.name}</li>`).join("");
    }
  });
})();
