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
}());
