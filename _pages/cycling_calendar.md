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
{% if event.description %}
{% assign desc_lines = event.description | strip | split: "
" %}
{% assign in_urls = false %}
{% assign event_text = "" %}
{% assign event_urls = "" | split: "" %}
{% for line in desc_lines %}
  {% assign trimmed = line | strip %}
  {% if trimmed contains "text:" %}
    {% assign event_text = trimmed | remove_first: "text:" | strip %}
  {% elsif trimmed == "urls:" %}
    {% assign in_urls = true %}
  {% elsif in_urls and trimmed != "" and trimmed contains "- " %}
    {% assign url = trimmed | remove_first: "- " | strip %}
    {% assign event_urls = event_urls | push: url %}
  {% endif %}
{% endfor %}
{% if event_text != "" %}
**Details:** {{ event_text }}
{% endif %}
{% if event_urls.size > 0 %}
**Links:**
{% for url in event_urls %}
- [{{ url }}]({{ url }})
{% endfor %}
{% endif %}
{% endif %}

{% endfor %}
