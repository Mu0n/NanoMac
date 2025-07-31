/*
  nanomactracker.r
*/

#include "Dialogs.r"

resource 'DLOG' (128) {
	{ 50, 100, 240, 420 },
	dBoxProc,
	visible,
	noGoAway,
	0,
	128,
	"",
	centerMainScreen
};

resource 'DITL' (128) {
	{
		{ 190-10-20, 320-10-80, 190-10, 320-10 },
		Button { enabled, "Quit" };

		{ 190-10-20-5, 320-10-80-5, 190-10+5, 320-10+5 },
		UserItem { enabled };

		{ 10, 10, 30, 310 },
		StaticText { enabled, "NanoMacTracker" };

		{ 40, 10, 56, 310 },
		StaticText { enabled, "..." };
	}
};

#include "Processes.r"

resource 'SIZE' (-1) {
	reserved,
	acceptSuspendResumeEvents,
	reserved,
	canBackground,
	doesActivateOnFGSwitch,
	backgroundAndForeground,
	dontGetFrontClicks,
	ignoreChildDiedEvents,
	is32BitCompatible,
	notHighLevelEventAware,
	onlyLocalHLEvents,
	notStationeryAware,
	dontUseTextEditServices,
	reserved,
	reserved,
	reserved,
	100 * 1024,
	100 * 1024
};
