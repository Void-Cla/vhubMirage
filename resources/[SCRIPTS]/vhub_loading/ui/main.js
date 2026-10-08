let rules = true
let gallery = true
let media = true
let team = true
let updates = true
let music = true
let video = true

function convertValue (value, oldMin, oldMax, newMin, newMax) {
    const oldRange = oldMax - oldMin
    const newRange = newMax - newMin
    const newValue = ((value - oldMin) * newRange) / oldRange + newMin
    return newValue
}

var muted = false;
let interval;
$(function () {
    $('#sounds').on("change", function(){
        muted = !muted;
        clearInterval(interval)
        if(muted) {
            let volume = 0.3;
            interval = setInterval(() => {
                if(volume > 0.00) {
                    volume -= 0.02
                    song.volume = volume;
                } else {
                    clearInterval(interval)
                    song.volume = .0;
                }
            }, 1);
        } else {
            let volume = 0.0;
            interval = setInterval(() => {
                if(volume < 1.00) {
                    volume += 0.02
                    song.volume = volume;
                } else {
                    clearInterval(interval)
                    song.volume = 0.3;
                }
            }, 1);
        }
    });
});

$(async function () {
    const Config = await fetch(`../../config.json`).then((res) => res.json())

    const safeFile = (value) => typeof value === 'string' && /^[\w.-]+$/.test(value) ? value : null
    const node = (tag, className, text) => {
        const element = document.createElement(tag)
        if (className) element.className = className
        if (text !== undefined) element.textContent = String(text)
        return element
    }

    for (const [key, data] of Object.entries(Config.Keys || {})) {
        const element = [...document.querySelectorAll('[data-key]')]
            .find(candidate => candidate.dataset.key === key)
        if (!element) continue
        element.classList.add('selectkey')
        element.addEventListener('click', () => {
            const info = node('div', 'keyInfo')
            const title = node('h2', '', data.title || '')
            title.append(node('p', '', data.description || ''))
            info.append(node('div', 'keyIcon', key.toLocaleUpperCase()), title)
            document.querySelector('.keyInfoBox')?.replaceChildren(info)
        })
    }

    $(".keyboardBox>div").data("key", function(){
        console.log()
    });

    const rulesList = document.querySelector('.rulesList')
    rulesList?.replaceChildren(...(Config.Rules || []).map(rule => {
        const box = node('div', 'rulesBox')
        const title = node('h2')
        title.append(node('span', '', rule.title || ''), node('p', '', rule.rule || ''))
        box.append(title)
        return box
    }))

    const images = (Config.Gallery || []).map(photo => {
        const file = safeFile(photo)
        if (!file) return null
        const image = node('img', 'galleryImg')
        image.src = `img/gallery/${file}`
        return image
    }).filter(Boolean)
    document.querySelector('.imagesWrapper')?.replaceChildren(...images)

    const team = (Config.Team || []).map(member => {
        const box = node('div', 'teamBox')
        const profile = node('div', 'teamProfileImg')
        const file = safeFile(member.img)
        if (file) profile.style.backgroundImage = `url("img/team/${file}")`
        box.append(profile, node('h2', 'teamRank', member.rank || ''), node('div', 'teamName', member.name || ''))
        return box
    })
    document.querySelector('.teamListBox')?.replaceChildren(...team)

    const updatesList = (Config.Updates || []).map(update => {
        const box = node('div', 'updateBox')
        const file = safeFile(update.img)
        if (file) box.style.backgroundImage = `url("img/updates/${file}")`
        const title = node('h2')
        title.append(node('span', '', update.title || ''), node('p', '', update.update || ''))
        box.append(title)
        return box
    })
    document.querySelector('.updateListBox')?.replaceChildren(...updatesList)

    $(".galleryImg").click(function(){
        $(".galleryBig img").attr("src", $(this).attr("src"))
        $(".galleryBig").fadeIn()
    })

    $(".galleryBig").click(function(){
        $(".galleryBig").fadeOut()
    })

    $("#hideBtn").click(function(){
        $("#rulesBtn").click()
        $("#galleryBox").click()
        $("#socialBtn").click()
        $("#teamBtn").click()
        $("#updatesBtn").click()
        $("#musicBtn").click()
    })

    $("#keysBtn").click(function(){
        $(".keyboardSide-wrapper").fadeIn()
    })

    $(".keyboardExitBox").click(function(){
        $(".keyboardSide-wrapper").fadeOut()
    })

    $("#videoHideBtn").click(function(){
        if(video){
            video = false
            $("#local-video").fadeOut()
        }else{
            video = true
            $("#local-video").fadeIn()
        }
    })

    $("#rulesBtn").click(function(){
        if(rules){
            rules = false
            $(".serverRules").css({
                transform: "translateX(-27vw)",
            })
            $(this).css({
                rotate: "180deg",
                transform: "translateX(-100px)",
            })
        }else{
            rules = true
            $(".serverRules").css({
                transform: "translateX(0)",
            })
            $(this).css({
                rotate: "0deg",
                transform: "translateX(0)",
            })
        }
    })

    $("#galleryBox").click(function(){
        if(gallery){
            gallery = false
            $(".galleryBox").css({
                transform: "translateX(-27vw)",
            })
            $(this).css({
                rotate: "180deg",
                transform: "translateX(-100px)",
            })
        }else{
            gallery = true
            $(".galleryBox").css({
                transform: "translateX(0)",
            })
            $(this).css({
                rotate: "0deg",
                transform: "translateX(0)",
            })
        }
    })

    $("#socialBtn").click(function(){
        if(media){
            media = false
            $(".socialMediaBox").css({
                transform: "translateX(-27vw)",
            })
            $(this).css({
                rotate: "180deg",
                transform: "translateX(-100px)",
            })
        }else{
            media = true
            $(".socialMediaBox").css({
                transform: "translateX(0)",
            })
            $(this).css({
                rotate: "0deg",
                transform: "translateX(0)",
            })
        }
    })

    $("#teamBtn").click(function(){
        if(team){
            team = false
            $(".authorizedTeamBox").css({
                transform: "translateX(24vw)",
            })
            $(this).css({
                rotate: "180deg",
                transform: "translateX(100px)",
            })
        }else{
            team = true
            $(".authorizedTeamBox").css({
                transform: "translateX(0)",
            })
            $(this).css({
                rotate: "0deg",
                transform: "translateX(0)",
            })
        }
    })

    $("#updatesBtn").click(function(){
        if(updates){
            updates = false
            $(".serverUpdateBox").css({
                transform: "translateX(24vw)",
            })
            $(this).css({
                rotate: "180deg",
                transform: "translateX(100px)",
            })
        }else{
            updates = true
            $(".serverUpdateBox").css({
                transform: "translateX(0)",
            })
            $(this).css({
                rotate: "0deg",
                transform: "translateX(0)",
            })
        }
    })

    $("#musicBtn").click(function(){
        if(music){
            music = false
            $(".serverMusicBox").css({
                transform: "translateX(24vw)",
            })
            $(this).css({
                rotate: "180deg",
                transform: "translateX(100px)",
            })
        }else{
            music = true
            $(".serverMusicBox").css({
                transform: "translateX(0)",
            })
            $(this).css({
                rotate: "0deg",
                transform: "translateX(0)",
            })
        }
    })

    $(".volumeBox input").on("change", function(){
        $(".volumeBox output").text($(this).val()+"%")
        audio.volume($(this).val() / 100)
    })

    function secondsToDuration(sec) {
		return `${Math.floor(sec / 60)
			.toString()
			.padStart(2, "0")}:${Math.round(sec % 60)
			.toString()
			.padStart(2, "0")}`
	}
	
	let audio = null
	let audioId = -1
	let audioInterval = null
	let audioTime = 0
	
	function stopAudio() {
		if (audio) {
			audio.stop()
	
			clearInterval(audioInterval)
	
			audio = null
			audioId = -1
			audioInterval = null
	
			$(".current-music span").text("Not Playing")
		}
	}
	
	function playAudio(id) {
		stopAudio()
	
		const music = Config.Music[id]
		const musicFile = music && typeof music.path === 'string'
			? music.path.match(/^musics\/([\w.-]+)$/) : null
	
		if (music && musicFile) {
			audio = new Howl({
				src: [`musics/${musicFile[1]}`],
				volume: $(".volumeBox input").val() / 100,
				onend: () => nextSong(),
			})
	
			resumeAudio()
			audioId = id
			audioInterval = setInterval(() => {
				if (audio.playing()) {
					$(".musicRightBox .custom-range").val((audio.seek() / audio.duration()) * 100)
                    $("#musicTime").text(secondsToDuration(audio.seek()))
				}
			}, 1000)
	
			$(".musicName span").text(music.name)
			$(".musicName p").text(music.author)
		}
	}

    $(".musicRightBox .custom-range").on("change", function(){
        audio.seek(convertValue($(this).val(), 0, 100, 0, audio.duration()))
    })
	
	function pauseAudio() {
		if (audio) {
			audio.pause()
	
			$("#play").show()
			$("#stop").hide()
		}
	}
	
	function resumeAudio() {
		if (audio) {
			audio.play()
	
			$("#play").hide()
			$("#stop").show()
		}
	}
	
	function nextSong(prev) {
		if (audio) {
			prev ? audioId-- : audioId++
	
			if (audioId >= Config.Music.length) audioId = 0
			else if (audioId < 0) audioId = Config.Music.length - 1
	
			playAudio(audioId)
		}
	}
	
	$(function () {
		$("#play").click(() => resumeAudio())
		$("#stop").click(() => pauseAudio())
		$("#next").click(() => nextSong())
		$("#prev").click(() => nextSong(true))
	
		playAudio(0)
	})

    $(window).on("message", function ({ originalEvent: e }) {
		if (e.data.eventName === "loadProgress") {
			$(".loadingCar").css("width", (e.data.loadFraction * 100).toFixed(0) + "%")
			$(".loadingSay").text((e.data.loadFraction * 100).toFixed(0) + "%")
		}
	})

    const openExternal = (raw, allowedHosts) => {
        try {
            const url = new URL(raw)
            if (url.protocol !== 'https:' || !allowedHosts.includes(url.hostname.toLowerCase())) return
            window.invokeNative('openUrl', url.href)
        } catch (_) {}
    }
    $("#discord").click(() => openExternal(Config.Discord, ['discord.gg', 'www.discord.gg']))
    $("#instagram").click(() => openExternal(Config.Instagram, ['tiktok.com', 'www.tiktok.com', 'instagram.com', 'www.instagram.com']))
    $("#youtube").click(() => openExternal(Config.Youtube, ['youtube.com', 'www.youtube.com', 'youtu.be']))
});
