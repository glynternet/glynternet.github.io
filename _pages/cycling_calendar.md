---
layout: page
title: Cycling Calendar
permalink: /cycling/calendar
tags: cycling
---

# 📅

<style>
.event { margin-bottom: 2em; }
.year-heading { margin-bottom: 1em; }
</style>

<div id="future-events"></div>
<div id="past-events"></div>

<script>
const eventsData = {{ site.data.cycling_events.events | jsonify }};
const seriesData = {{ site.data.cycling_events.series | jsonify }};

function formatEvent(event) {
  let html = `<div class="event">\n`;
  html += `<h3>${event.summary}</h3>\n`;
  html += `<p><strong>Begin:</strong> ${event.begin}</p>\n`;
  if (event.end) {
    html += `<p><strong>End:</strong> ${event.end}</p>\n`;
  }
  if (event.location) {
    html += `<p><strong>Location:</strong> ${event.location.trim()}</p>\n`;
  }

  if (event.series) {
    const seriesInfo = seriesData[event.series];
    if (seriesInfo && seriesInfo.url) {
      html += `<p><strong>Series:</strong> <a href="${seriesInfo.url}">${event.series}</a></p>\n`;
    } else {
      html += `<p><strong>Series:</strong> ${event.series}</p>\n`;
    }
  }

  if (event.description) {
    html += `<p><strong>Details:</strong> ${event.description}</p>\n`;
  }

  if (event.urls && event.urls.length > 0) {
    html += `<p><strong>Links:</strong></p>\n<ul>\n`;
    event.urls.forEach(url => {
      html += `<li><a href="${url}">${url}</a></li>\n`;
    });
    html += `</ul>\n`;
  }

  html += `</div>\n`;
  return html;
}

function renderEvents() {
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const futureEvents = [];
  const pastEvents = [];

  eventsData.filter(event => event.attending !== false).forEach(event => {
    const eventDate = new Date(event.begin + 'T00:00:00');
    if (eventDate >= today) {
      futureEvents.push(event);
    } else {
      pastEvents.push(event);
    }
  });

  // Sort future events ascending (soonest first)
  futureEvents.sort((a, b) => a.begin.localeCompare(b.begin));
  // Sort past events descending (most recent first)
  pastEvents.sort((a, b) => b.begin.localeCompare(a.begin));

  let futureHtml = '';
  let currentYear = '';

  if (futureEvents.length > 0) {
    futureHtml += '<h2>Upcoming Events</h2>\n';
    futureEvents.forEach(event => {
      const eventYear = event.begin.slice(0, 4);
      if (eventYear !== currentYear) {
        currentYear = eventYear;
        futureHtml += `<h2 class="year-heading">${currentYear}</h2>\n`;
      }
      futureHtml += formatEvent(event);
    });
  }

  let pastHtml = '';
  currentYear = '';

  if (pastEvents.length > 0) {
    pastHtml += '<h2>Past Events</h2>\n';
    pastEvents.forEach(event => {
      const eventYear = event.begin.slice(0, 4);
      if (eventYear !== currentYear) {
        currentYear = eventYear;
        pastHtml += `<h2 class="year-heading">${currentYear}</h2>\n`;
      }
      pastHtml += formatEvent(event);
    });
  }

  document.getElementById('future-events').innerHTML = futureHtml;
  document.getElementById('past-events').innerHTML = pastHtml;
}

document.addEventListener('DOMContentLoaded', renderEvents);
</script>
