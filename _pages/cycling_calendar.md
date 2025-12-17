---
layout: page
title: Cycling Calendar
permalink: /cycling/calendar
tags: cycling
---

# 📅

{% assign sorted_events = site.data.cycling_events.events | sort: "begin" | reverse %}
{% assign current_year = "" %}

{% for event in sorted_events %}
  {% assign event_year = event.begin | slice: 0, 4 %}
  {% if event_year != current_year %}
    {% assign current_year = event_year %}
## {{ current_year }}
  {% endif %}

### {{ event.begin }} - {{ event.summary }}
**Location:** {{ event.location | strip }}
{% if event.series %}
{% assign series_info = site.data.cycling_events.series[event.series] %}
{% if series_info.url %}
**Series:** [{{ event.series }}]({{ series_info.url }})
{% else %}
**Series:** {{ event.series }}
{% endif %}
{% endif %}
{% if event.description %}
**Details:** {{ event.description }}
{% endif %}
{% if event.urls.size > 0 %}
**Links:**
{% for url in event.urls %}
- [{{ url }}]({{ url }})
{% endfor %}
{% endif %}

{% endfor %}
