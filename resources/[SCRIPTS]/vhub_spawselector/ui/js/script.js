$(function () {
    const resourceName = GetParentResourceName();
    let isOpen = false;
    let revealTimer = null;
    let submitTimer = null;

    function clearTimers() {
        if (revealTimer) clearTimeout(revealTimer);
        if (submitTimer) clearTimeout(submitTimer);
        revealTimer = null;
        submitTimer = null;
    }

    function hideUI() {
        isOpen = false;
        clearTimers();
        $(document).off(".spawnselector");
        $("body").stop(true, true).hide();
        $(".container").empty();
        $(".container-down").css("bottom", "-4vw");
    }

    function submitSpawn(index) {
        if (!isOpen || submitTimer) return;

        submitTimer = setTimeout(() => {
            submitTimer = null;
            if (!isOpen) return;
            $.post(`https://${resourceName}/teleport`, JSON.stringify({ index }));
            hideUI();
        }, 250);
    }

    function bindInteractions() {
        $(document)
            .off(".spawnselector")
            .on("click.spawnselector", ".select", function () {
                if (!isOpen || submitTimer) return;
                $(this).text("Selecionado");
                submitSpawn(Number($(this).attr("data-index")));
            })
            .on("click.spawnselector", ".container-down", function () {
                submitSpawn(undefined);
            })
            .on("keyup.spawnselector", function (event) {
                if (event.key === "Escape" || event.which === 27) submitSpawn(undefined);
            });
    }

    function setupUI(location) {
        if (!location || !Array.isArray(location.data)) return;

        hideUI();
        $(".container").empty();

        location.data.forEach((data, rawIndex) => {
            const index = rawIndex + 1;
            const inputId = `spawn-${index}`;
            const image = /^[\w.-]+$/.test(String(data.Image || "")) ? data.Image : "parking.png";
            const input = $("<input>", { type: "radio", name: "slide", id: inputId })
                .prop("checked", index === 1);
            const label = $("<label>", { class: "card", for: inputId })
                .css("background-image", `url("images/${image}")`);
            const row = $("<div>", { class: "row" });
            const description = $("<div>", { class: "description" })
                .append($("<h4>").text(String(data.Name || "Local")))
                .append($("<p>").text(String(data.Description || "")));

            row.append($("<div>", { class: "icon" }).text(`${index} L`));
            row.append(description);
            row.append($("<div>", { class: "select", "data-index": index }).text("Escolher"));
            label.append(row);
            $(".container").append(input, label);
        });

        if (location.last) {
            $(".main-description h4").text(String(location.last.Name || ""));
            $(".main-description p").text(String(location.last.Description || ""));
            $(".main-icon").text(String(location.last.MiniTxt || ""));
        }

        isOpen = true;
        bindInteractions();
        $("body").stop(true, true).fadeIn(160);
        revealTimer = setTimeout(() => {
            revealTimer = null;
            if (!isOpen) return;
            $(".container-down").css("bottom", "1vw");
        }, 160);
    }

    window.addEventListener('message', function (event) {
        if (event.data.action === 'open') {
            setupUI(event.data);
        } else if (event.data.action === 'close') {
            hideUI();
        }
    });

    window.addEventListener("beforeunload", hideUI);
    hideUI();
});
