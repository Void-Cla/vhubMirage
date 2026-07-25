let openedDays = {};
let currentDay = 0;
let testMode = false;

function getCurrentDay() {
    const today = new Date();
    const currentMonth = today.getMonth() + 1;
    
    if (currentMonth !== 12) {
        return 0;
    }
    
    return today.getDate();
}

function createCalendar() {
    const grid = $('#adventGrid');
    grid.empty();
    
    if (!testMode) {
        currentDay = getCurrentDay();
    } else {
        currentDay = 31;
    }
    
    for (let i = 1; i <= 31; i++) {
        const dayBox = $('<div>').addClass('advent-day').attr('data-day', i);
        
        if (i > currentDay && !testMode) {
            dayBox.addClass('locked');
        } else if (openedDays[i]) {
            dayBox.addClass('opened');
        }
        
        const dayNumber = $('<div>').addClass('day-number').text(i);
        dayBox.append(dayNumber);
        
        if (openedDays[i]) {
            const icon = $('<div>').addClass('day-icon').html('<i class="fas fa-gift"></i>');
            dayBox.append(icon);
        } else if (i <= currentDay || testMode) {
            const icon = $('<div>').addClass('day-icon').html('<i class="fas fa-lock-open"></i>');
            dayBox.append(icon);
        } else {
            const icon = $('<div>').addClass('day-icon').html('<i class="fas fa-lock"></i>');
            dayBox.append(icon);
        }
        
        if ((i <= currentDay || testMode) && !openedDays[i]) {
            dayBox.on('click', function() {
                const day = $(this).data('day');
                openDay(day);
            });
        }
        
        grid.append(dayBox);
    }
}

function openDay(day) {
    const dayBox = $(`.advent-day[data-day="${day}"]`);
    
    if (dayBox.hasClass('opened') || dayBox.hasClass('locked')) {
        return;
    }
    
    dayBox.addClass('day-opening');
    
    $.post('https://caticus-advent/openDay', JSON.stringify({
        day: day
    }));
}

function showRewardPopup(reward) {
    $('#rewardText').text(reward);
    $('#rewardPopup').fadeIn(300);
    
    setTimeout(() => {
        $('#rewardPopup').fadeOut(300);
    }, 3000);
}

function createSnowflakes() {
    const wrapper = $('.advent-wrapper');
    
    for (let i = 0; i < 20; i++) {
        const snowflake = $('<div>').addClass('snowflake').html('❄');
        snowflake.css({
            left: Math.random() * 100 + '%',
            animationDuration: (Math.random() * 3 + 2) + 's',
            animationDelay: Math.random() * 2 + 's',
            fontSize: (Math.random() * 10 + 15) + 'px',
            opacity: Math.random() * 0.5 + 0.5
        });
        wrapper.append(snowflake);
    }
}

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.action === 'openCalendar') {
        openedDays = {};
        if (data.calendarData) {
            for (let day in data.calendarData) {
                openedDays[parseInt(day)] = true;
            }
        }
        testMode = data.testMode || false;
        $('#adventTitle').text(data.title || 'Advent Calendar 2025');
        $('#adventContainer').fadeIn(300);
        createCalendar();
        createSnowflakes();
    }
    
    if (data.action === 'closeCalendar') {
        $('#adventContainer').fadeOut(300);
        $('.snowflake').remove();
    }
    
    if (data.action === 'dayOpened') {
        const dayBox = $(`.advent-day[data-day="${data.day}"]`);
        dayBox.removeClass('day-opening');
        dayBox.addClass('opened');
        dayBox.off('click');
        
        const icon = $('<div>').addClass('day-icon').html('<i class="fas fa-gift"></i>');
        dayBox.find('.day-icon').replaceWith(icon);
        
        openedDays[data.day] = true;
        
        if (data.reward) {
            showRewardPopup('Day ' + data.day + ' Reward: ' + data.reward);
        }
    }
    
    if (data.action === 'alreadyOpened') {
        const dayBox = $(`.advent-day[data-day="${data.day}"]`);
        dayBox.css('animation', 'shake 0.5s');
        setTimeout(() => {
            dayBox.css('animation', '');
        }, 500);
    }
    
    if (data.action === 'updateCalendar') {
        openedDays = {};
        if (data.calendarData) {
            for (let day in data.calendarData) {
                openedDays[parseInt(day)] = true;
            }
        }
        createCalendar();
    }
});

$(document).ready(function() {
    $('#closeBtn').on('click', function() {
        $.post('https://caticus-advent/closeCalendar', JSON.stringify({}));
    });
    
    $(document).keyup(function(event) {
        if (event.key === 'Escape') {
            $.post('https://caticus-advent/closeCalendar', JSON.stringify({}));
        }
    });
});

