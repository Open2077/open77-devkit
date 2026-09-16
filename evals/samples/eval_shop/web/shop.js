// eval_shop page script. It renders what the client Lua sends with page:send()
// and raises events with Open77.emit() for page:on(). Nothing here touches the
// network and nothing here holds a price: the list is whatever the server sent.
(function () {
  "use strict";

  var bridge = window.Open77;
  var handlers = {};

  function emit(name, payload) {
    if (bridge && typeof bridge.emit === "function") {
      bridge.emit(name, payload || {});
    }
  }

  function on(name, handler) {
    handlers[name] = handler;
    if (bridge && typeof bridge.on === "function") {
      bridge.on(name, handler);
    }
  }

  // Fallback delivery shape for page:send(): a window message carrying
  // { event, payload } (or { kind, ... } as the devkit scaffold uses).
  window.addEventListener("message", function (e) {
    var data = e.data || {};
    var name = data.event || data.name || data.kind;
    if (name && handlers[name]) {
      handlers[name](data.payload !== undefined ? data.payload : data);
    }
  });

  var itemsEl = document.getElementById("items");
  var balanceEl = document.getElementById("balance");

  function setBalance(value) {
    balanceEl.textContent = typeof value === "number" ? String(value) : "–";
  }

  function renderItems(items) {
    itemsEl.textContent = "";
    if (!Array.isArray(items) || items.length === 0) {
      var empty = document.createElement("li");
      empty.className = "empty";
      empty.textContent = "Nothing for sale right now.";
      itemsEl.appendChild(empty);
      return;
    }
    items.forEach(function (item) {
      if (!item || typeof item.id !== "string") return;
      var li = document.createElement("li");

      var name = document.createElement("span");
      name.className = "name";
      name.textContent = String(item.name || item.id);

      var price = document.createElement("span");
      price.className = "price";
      price.textContent = (typeof item.price === "number" ? item.price : "?") + " E$";

      var buy = document.createElement("button");
      buy.type = "button";
      buy.textContent = "Buy";
      buy.addEventListener("click", function () {
        // Only the id travels. The server decides what it costs.
        emit("buy", { id: item.id });
      });

      li.appendChild(name);
      li.appendChild(price);
      li.appendChild(buy);
      itemsEl.appendChild(li);
    });
  }

  on("catalog", function (payload) {
    payload = payload || {};
    renderItems(payload.items);
    setBalance(payload.balance);
  });

  on("balance", function (payload) {
    setBalance(payload ? payload.balance : undefined);
  });

  document.getElementById("close").addEventListener("click", function () {
    emit("close");
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" || e.key === "F6") {
      e.preventDefault();
      emit("close");
    }
  });

  emit("ready");
})();
