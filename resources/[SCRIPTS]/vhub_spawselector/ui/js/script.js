$(function () {
    const resourceName = GetParentResourceName();

    function setupUI(Location) {
        $(".container").empty();
        let index = 0;
        Location.data.forEach(data => {
            index += 1;
            $(".container").append(`
                <input type="radio" name="slide" id="${index}" ${index == 1 ? "checked" : ""}>
                <label class="card" for="${index}" style="background-image: url('images/${data.Image}');">
                    <div class="row">
                        <div class="icon">${index} L</div>
                        <div class="description">
                            <h4>${data.Name}</h4>
                            <p>${data.Description}</p>
                        </div>
                        <div class="select" index="${index}">Select</div>
                    </div>
                </label>`);
        });

        if (Location.last) {
            $(".main-description h4").text(Location.last.Name);
            $(".main-description p").text(Location.last.Description);
            $(".main-icon").text(Location.last.MiniTxt);
        }

        $("body").fadeIn(500);
        setTimeout(() => {
            $(".container-down").css("bottom", "1vw");
        }, 400);
    }

    // Escuta evento 'open' do vHub
    window.addEventListener('message', function (event) {
        if (event.data.action === 'open') {
            setupUI(event.data);
        }
    });

    // Fallback para o método antigo (opcional, mas mantido para compatibilidade)
    setTimeout(() => {
        if ($("body").is(":hidden")) {
            $.post(`https://${resourceName}/RequestLoadUIData`, function (Location) {
                if (Location) setupUI(Location);
            });
        }
    }, 700);

    $(document).on("click", ".select", function () {
        const index = $(this).attr("index");
        const $btn = $(this);
        
        $btn.text("Selected");
        $btn.css({ "left": "-7vw", "width": "5.604vw" });

        setTimeout(() => {
            $.post(`https://${resourceName}/teleport`, JSON.stringify({ index }));
            $("body").fadeOut(500);
        }, 400);
    });

    function Exit() {
        $(".container-down").css("bottom", "-4vw");
        $.post(`https://${resourceName}/teleport`, JSON.stringify({}));
        $("body").fadeOut(500);
    }

    $(document).on("click", ".container-down", Exit);
    
    document.addEventListener("keyup", function (data) {
        if (data.which == 27) {
            Exit();
        }
    });
});
