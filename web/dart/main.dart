// Copyright (C) 2019 Hendrik Fichtenberger
// 
// This file is part of Klausuransicht.
// 
// Klausuransicht is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// Klausuransicht is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with Klausuransicht.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:collection';
import 'dart:convert';
import 'dart:html';
import 'dart:async';
import 'dart:js';

List<String> placeholders = ['veranstaltungsname', 'teilnehmerbereich'];
List<String> others = ['progressbar', 'countdown', 'klausurbeginn', 'klausurende'];
//List<String> selects = [];
List<String> necessary = [];
List<String> recommended = ['veranstaltungsname'];
Map<String, String> values = {};

List<LIElement> zusatzhinweise = [];

DateTime time_klausurbeginn = DateTime.now();
DateTime time_klausurende = DateTime.now();
bool validTimes = false;

var timecounter;
var timediff = Duration();

void main() {
  // Load instance if provided
  if (Uri.base.queryParameters.containsKey("txt")) {
    load(Uri.base.queryParameters["txt"]);
  }

	// Hook up events
	for (String placeholder in placeholders) {
		getInput(placeholder).onKeyUp.listen(triggerChange);
	}
	for (String other in others) {
		getInput(other).onChange.listen(triggerChange);
		getInput(other).onKeyUp.listen(triggerChange);
	}
	/*for (String select in selects) {
		getSelect(select).onChange.listen(triggerChange);
	}*/

	querySelector('#button_config').onClick.listen(buttonConfig);
	querySelector('#button_hinweise').onClick.listen(buttonHinweise);
	querySelector('#button_zeit').onClick.listen(buttonZeit);
	querySelector('#button_minmin').onClick.listen(buttonMinMin);
	querySelector('#button_ressec').onClick.listen(buttonResSec);
	querySelector('#button_plumin').onClick.listen(buttonPluMin);
  querySelector('#button_save').onClick.listen(buttonSave);
  querySelector('#save_url').onClick.listen(inputSaveUrl);

	querySelector('#burger').onClick.listen(burgerClick);
	for (Element elem in querySelectorAll('.delete')) {
		elem.onClick.listen((Event e) {
			for (Element elem2 in querySelectorAll('.${elem.id}_outer')) {
				elem2.remove();
			}
		});
	}

  // Init CKEditor on .ckeditor elements
  var ckeditor = context['InlineEditor'];
	for (Element elem in querySelectorAll('.ckeditor')) {
		ckeditor.callMethod('create', [elem]);
	}

	// Set up clock
	timecounter = Timer.periodic(Duration(seconds: 1), triggerTime);

	// Update UI
	updateChange();
	countTime();

	// Hide loading spinner
	unhide(querySelector('#navbar'));
	unhide(querySelector('#part_config'));
	hide(querySelector('#part_live'));
	hide(querySelector('#preload'));
}

InputElement getInput(String name) {
	return querySelector('#inp_${name}');
}

SelectElement getSelect(String name) {
	return querySelector('#inp_${name}');
}

Element getText(String name) {
	return querySelector('#txt_${name}');
}

Element getHelper(String name, String helper) {
	return querySelector('#help_${name}_${helper}');
}


void triggerChange(Event e) {
	updateChange();
}

void updateChange() {
	// Update placeholder texts
	for (String placeholder in placeholders) {
		values[placeholder] = getInput(placeholder).value;
		getText(placeholder)?.text = values[placeholder];
		bool try_next = true;
		for (int i = 1; try_next; i++) {
			Element next = getText('${placeholder}_${i}');
			next?.text = values[placeholder];
			try_next = next != null;
		}
		Element helper = getHelper(placeholder, 'hint');
		if (!values[placeholder].isEmpty && helper != null) {
			getHelper(placeholder, 'innerhint').text = values[placeholder];
			setVisibility(helper);
		}
		else if (helper != null) {
			hide(helper);
		}
	}
	for (String other in others) {
		InputElement e = getInput(other);
		if(e.type == "checkbox") {
			values[other] = e.checked.toString();
		}
		else {
			values[other] = e.value;
		}
	}
	/*for (String select in selects) {
		values[select] = getSelect(select).value;
	}*/

	// Flags for optional UI elements
	bool progressbar_enabled = values['progressbar'] == 'true';
	bool countdown_enabled = values['countdown'] == 'true';
	bool times_enabled = progressbar_enabled || countdown_enabled;

	// Compute clock values
	RegExp expr = new RegExp(r'(\d\d?):(\d\d?)');
	Match mbeginn = expr.firstMatch(values['klausurbeginn']);
	Match mende = expr.firstMatch(values['klausurende']);
	if(mbeginn?.groupCount == 2 && mende?.groupCount == 2 ?? false) {
		DateTime now = DateTime.now();
		time_klausurbeginn = new DateTime(now.year, now.month, now.day, int.parse(mbeginn.group(1)), int.parse(mbeginn.group(2)));
		time_klausurende = new DateTime(now.year, now.month, now.day, int.parse(mende.group(1)), int.parse(mende.group(2)));
		validTimes = true;
	}
	else {
		validTimes = false;
	}
	bool invalid_beginn = times_enabled && mbeginn?.groupCount != 2 ?? true;
	manageClass(getInput('klausurbeginn'), 'is-warning', invalid_beginn);
	setVisibility(getHelper('klausurbeginn', 'invalidformat'), invalid_beginn);
	bool invalid_ende = times_enabled && mende?.groupCount != 2 ?? true;
	manageClass(getInput('klausurende'), 'is-warning', invalid_ende);
	setVisibility(getHelper('klausurende', 'invalidformat'), invalid_ende);

	// Visibility of optional UI elements
	setVisibility(querySelector('#header_small'), values['teilnehmerbereich'].isEmpty);
	setVisibility(querySelector('#header_large'), !values['teilnehmerbereich'].isEmpty);
	setVisibility(querySelector('#elem_progressbar'), progressbar_enabled && validTimes);
	setVisibility(querySelector('#elem_countdown'), countdown_enabled && validTimes);

	// Show hints for empty inputs
	var handleIsEmpty = (elements, hinttype) {
		for (String setting in elements)
		{
			if(values[setting].isEmpty) {
				manageClass(getInput(setting), 'is-${hinttype}', true);
				setVisibility(getHelper(setting, "isempty"));
			}
			else {
				manageClass(getInput(setting), 'is-${hinttype}', false);
				hide(getHelper(setting, "isempty"));
			}
		}
	};
	handleIsEmpty(necessary, 'danger');
	handleIsEmpty(recommended, 'info');
}

void triggerTime(Timer t) {
	countTime();
}

void countTime() {
	// Update clock
	DateTime synctime = DateTime.now().add(timediff);
	(querySelector('#time1') as InputElement).value = "${synctime.hour}:${synctime.minute.toString().padLeft(2, '0')}:${synctime.second.toString().padLeft(2, '0')}";
	querySelector('#time2').text = "${synctime.hour}:${synctime.minute.toString().padLeft(2, '0')}";
	if (!validTimes) {
		return;
	}

	// Update progressbar and countdown
	Duration totaltime = time_klausurende.difference(time_klausurbeginn);
	Duration elapsed = synctime.difference(time_klausurbeginn);
	Duration remaining = time_klausurende.difference(synctime);
	int progress = 100;
	if(remaining.inMilliseconds > 0) {
		progress = (100 * elapsed.inSeconds / totaltime.inSeconds).round();
		progress = progress < 0 ? 0 : progress;
		progress = progress > 100 ? 100 : progress;
	}
	(querySelector('#elem_progressbar') as ProgressElement).value = progress;
	int min_remaining = remaining.inMinutes + 1;
	if (min_remaining > 1) {
		(querySelector('#elem_countdown')).text = "Noch ${remaining.inMinutes+1} Minuten";
	}
	else {
		(querySelector('#elem_countdown')).text = "Weniger als 1 Minute";
	}
}

void hide(Element e) {
	e.classes.add('is-hidden');
}

void unhide(Element e) {
	e.classes.remove('is-hidden');
}

void setVisibility(Element e, [bool show = true]) {
	if(show) {
		unhide(e);
	}
	else {
		hide(e);
	}
}

void manageClass(Element e, String c, bool add) {
	if(add) {
		e.classes.add(c);
	}
	else {
		e.classes.remove(c);
	}
}

void burgerClick(Event e) {
	querySelector('#burger').classes.toggle('is-active');
	querySelector('#menu').classes.toggle('is-active');
}

void buttonConfig(Event e) {
	hide(querySelector('#part_live'));
	unhide(querySelector('#part_config'));
}

void buttonHinweise(Event e) {
	hide(querySelector('#part_config'));
	unhide(querySelector('#part_live'));
	hide(querySelector('#part_live_zeit'));
	unhide(querySelector('#part_live_vor'));
}

void buttonZeit(Event e) {
	hide(querySelector('#part_config'));
	unhide(querySelector('#part_live'));
	hide(querySelector('#part_live_vor'));
	unhide(querySelector('#part_live_zeit'));
}

void buttonMinMin(Event e) {
	timediff = timediff + Duration(minutes: -1);
	countTime();
}

void buttonResSec(Event e) {
	DateTime synctime = DateTime.now().add(timediff);
	timediff = timediff + Duration(seconds: -synctime.second);
	countTime();
}

void buttonPluMin(Event e) {
	timediff = timediff + Duration(minutes: 1);
	countTime();
}

void buttonSave(Event e) {
	var storage = new HashMap<String,String>();
  for (Element elem in querySelectorAll('.ckeditor')) {
    storage[elem.id] = elem.innerHtml;
  }
  var suffix = "?txt=" + Uri.encodeComponent(utf8.fuse(base64).encode(jsonEncode(storage)));
  if (Uri.base.isScheme("file")) {
    (querySelector('#save_url') as InputElement).value = Uri.base.scheme + "://" + Uri.base.path + suffix;
  } else {
    (querySelector('#save_url') as InputElement).value = Uri.base.origin + Uri.base.path + suffix;
  }
}

void inputSaveUrl(Event e) {
  TextInputElement elem = querySelector('#save_url');
  elem.setSelectionRange(0, elem.value.length);
}

void load(String encoding) {
  var storage = jsonDecode(utf8.fuse(base64).decode(encoding));
  for (Element elem in querySelectorAll('.ckeditor')) {
    if(storage.containsKey(elem.id)) {
      elem.innerHtml = storage[elem.id];
    }
  }
}