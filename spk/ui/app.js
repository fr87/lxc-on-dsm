(function () {
    "use strict";

    function setText(id, text) {
        var element = document.getElementById(id);
        if (element) {
            element.textContent = text;
        }
    }

    function yesNo(value) {
        return value ? "yes" : "no";
    }

    function byId(id) {
        return document.getElementById(id);
    }

    function safeName(value, fallback) {
        var trimmed = String(value || "").trim();
        if (/^[A-Za-z0-9_.-]+$/.test(trimmed)) {
            return trimmed;
        }
        return fallback;
    }

    function safeInterface(value, fallback) {
        var trimmed = String(value || "").trim();
        if (/^[A-Za-z0-9_.:-]+$/.test(trimmed) && trimmed.length <= 15) {
            return trimmed;
        }
        return fallback;
    }

    function updateCommands() {
        var name = safeName(byId("container-name") && byId("container-name").value, "alpine-lab");
        var network = byId("network-type") ? byId("network-type").value : "none";
        var parentIf = safeInterface(byId("parent-if") && byId("parent-if").value, "eth0");
        var list = "sh /var/packages/lxc-on-dsm/target/scripts/list-packaged-containers.sh";
        var create = "sh /var/packages/lxc-on-dsm/target/scripts/create-packaged-container.sh --name " + name;
        var start = [
            "sh /var/packages/lxc-on-dsm/target/scripts/start-packaged-container.sh --name " + name,
            "sh /var/packages/lxc-on-dsm/target/scripts/start-packaged-container.sh --name " + name + " --run"
        ].join("\n");
        var hook = [
            "sh /var/packages/lxc-on-dsm/target/scripts/install-packaged-start-hook.sh --name " + name,
            "sh /var/packages/lxc-on-dsm/target/scripts/install-packaged-start-hook.sh --name " + name + " --install"
        ].join("\n");
        var snippet = [
            "sh /var/packages/lxc-on-dsm/target/scripts/install-packaged-hook-snippet.sh --name " + name + " --snippet 10-marker --source /var/packages/lxc-on-dsm/target/hooks/marker.example.sh",
            "sh /var/packages/lxc-on-dsm/target/scripts/install-packaged-hook-snippet.sh --name " + name + " --snippet 10-marker --source /var/packages/lxc-on-dsm/target/hooks/marker.example.sh --install"
        ].join("\n");
        var stop = "sh /var/packages/lxc-on-dsm/target/scripts/stop-packaged-container.sh --name " + name;
        var exec = [
            "sh /var/packages/lxc-on-dsm/target/scripts/exec-packaged-container.sh --name " + name + " --run -- hostname",
            "sh /var/packages/lxc-on-dsm/target/scripts/exec-packaged-container.sh --name " + name + " --run -- /bin/sh"
        ].join("\n");
        var test;

        if (network === "macvlan") {
            create += " --network-type macvlan --parent-if " + parentIf + " --create";
            test = [
                "sh /var/packages/lxc-on-dsm/target/scripts/run-packaged-macvlan-dhcp-test.sh --name " + name,
                "sh /var/packages/lxc-on-dsm/target/scripts/run-packaged-macvlan-dhcp-test.sh --name " + name + " --run"
            ].join("\n");
            setText("builder-hint", "macvlan mode uses the selected parent only as a macvlan parent. It does not bridge or reconfigure DSM networking.");
        } else if (network === "none") {
            create += " --network-type none --create";
            start = "# Persistent start is intentionally disabled for lxc.net.0.type = none.\n# Use the smoke test below, or choose empty/macvlan for a running container.";
            hook = "# The hook dispatcher is intended for persistent empty/macvlan containers.";
            snippet = "# Hook snippets are intended for persistent empty/macvlan containers.";
            stop = "# No persistent none-mode container was started by this flow.";
            exec = "# No persistent none-mode container is running in this flow.";
            test = "sh /var/packages/lxc-on-dsm/target/scripts/run-packaged-smoke-test.sh --name " + name;
            setText("builder-hint", "none mode is kept for the short smoke test only. For a persistent isolated container, choose empty mode.");
        } else {
            create += " --network-type empty --create";
            test = "sh /var/packages/lxc-on-dsm/target/scripts/list-packaged-containers.sh";
            setText("builder-hint", "empty mode creates an isolated network namespace and is the safest persistent first container.");
        }

        setText("cmd-list", list);
        setText("cmd-create", create);
        setText("cmd-test", test);
        setText("cmd-start", start);
        setText("cmd-hook", hook);
        setText("cmd-snippet", snippet);
        setText("cmd-stop", stop);
        setText("cmd-exec", exec);
    }

    function wireCommandBuilder() {
        ["container-name", "network-type", "parent-if"].forEach(function (id) {
            var element = byId(id);
            if (element) {
                element.addEventListener("input", updateCommands);
                element.addEventListener("change", updateCommands);
            }
        });

        Array.prototype.forEach.call(document.querySelectorAll("[data-copy]"), function (button) {
            button.addEventListener("click", function () {
                var target = byId(button.getAttribute("data-copy"));
                var value = target ? target.textContent : "";
                if (navigator.clipboard && value) {
                    navigator.clipboard.writeText(value).then(function () {
                        button.textContent = "Copied";
                        window.setTimeout(function () {
                            button.textContent = "Copy";
                        }, 1200);
                    }).catch(function () {
                        button.textContent = "Select text";
                    });
                }
            });
        });

        updateCommands();
    }

    fetch("status.json", { cache: "no-store" })
        .then(function (response) {
            if (!response.ok) {
                throw new Error("status.json unavailable");
            }
            return response.json();
        })
        .then(function (status) {
            setText("status-package", status.package || "unknown");
            setText("status-version", status.version || "unknown");
            setText("status-runtime", yesNo(status.runtime_bundle_packaged));
            setText("status-image", yesNo(status.alpine_image_packaged));
            setText("status-mode", status.mode || "lab");
        })
        .catch(function () {
            setText("status-package", "lxc-on-dsm");
            setText("status-version", "unknown");
            setText("status-runtime", "unknown");
            setText("status-image", "unknown");
            setText("status-mode", "static fallback");
        });

    wireCommandBuilder();
}());
