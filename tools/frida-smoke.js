const symbol = Process.mainModule.enumerateSymbols().find(
  (entry) => entry.name === "macpocket_add"
);
if (!symbol) throw new Error("macpocket_add symbol was not found");
Interceptor.attach(symbol.address, {
  onEnter(args) {
    send({ test: "macpocket", left: args[0].toInt32(), right: args[1].toInt32() });
  },
  onLeave(value) {
    send({ test: "macpocket-result", result: value.toInt32() });
  },
});
