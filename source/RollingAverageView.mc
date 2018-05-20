using Toybox.WatchUi as Ui;
using Toybox.Math;
using Toybox.System as Sys;
using Toybox.Application as App;
using Toybox.Application.Properties as Props;
//using Toybox.Test;

const cDistAverageOver = 25; // Distance (m) over which to average Rate
const distAccuracy = 2; // within how many metres ? or should it be a % ?

const cTimeAverageOver = 25; // Time (ms) over which to average Rate
const timeAccuracy = 0; // within how many seconds ? or should it be a % ?

const bufLen = 600; // max number of points

const cShowPace = true;
const cUseDist = true;

class RollingAverageView extends Ui.SimpleDataField {

    enum
    {
        OFF,
        STOPPED,
        PAUSED,
        RUNNING
    }

	hidden var mDistAverageOver = 25; // Distance (m) over which to average Rate
	hidden var mTimeAverageOver = 25; // Time (s) over which to average Rate
	hidden var mShowPace = true;
	hidden var mUseDist = true;

    hidden var mTimerState = OFF;

	hidden var mTimes = new [bufLen];
	hidden var mDists = new [bufLen];

    hidden var mOldest  = 0;
    hidden var mCurrent = 0;

    hidden var mVal	  = "";
/*
const RAND_MAX = 0x7FFFFFFF;
function random(m, n) {
    return m + Math.rand() / (RAND_MAX / (n - m + 1) + 1);
}
*/
    // Set the label of the data field here.
    function initialize() {
        var tDistAverageOver;		
		var tTimeAverageOver;
		
        SimpleDataField.initialize();
        
        mTimes[0] = 0;
        mDists[0] = 0;
        label = "Mov. Avg.";
        if ( App has :Properties ) {
        	tDistAverageOver = Props.getValue("distAverageOver");
	        tTimeAverageOver = Props.getValue("timeAverageOver");
	        mShowPace = Props.getValue("showPace");
	        mUseDist = Props.getValue("useDist");
	    } else {
			var thisApp = App.getApp();
	    	tDistAverageOver = thisApp.getProperty("distAverageOver");
	    	tTimeAverageOver = thisApp.getProperty("timeAverageOver");
	        mShowPace = thisApp.getProperty("showPace");
	        mUseDist = thisApp.getProperty("useDist");
	    }
        
        if (tDistAverageOver == null) {
        	tDistAverageOver = cDistAverageOver;
        }
       	mDistAverageOver = tDistAverageOver.toNumber();
       	
        if (tTimeAverageOver == null) {
        	tTimeAverageOver = cTimeAverageOver;
        }
       	mTimeAverageOver = tTimeAverageOver.toNumber() * 1000;

        if (mUseDist == null) {
        	mUseDist = cUseDist;
        }

        if (mShowPace == null) {
        	mShowPace = cShowPace;
        }
        mVal = mShowPace ? "0:00" : "0.00";
    }


    //! The timer was started, so set the state to running.
    function onTimerStart()
    {
        mTimerState = RUNNING;
    }

    //! The timer was stopped, so set the state to stopped.
    //! and zero counters so we can restart from the beginning
    function onTimerStop()
    {
        mTimerState = STOPPED;
        mDists[0] = 0;
        mTimes[0] = 0;
        mOldest = 0;
        mCurrent = 0;
    }

    //! The timer was paused, so set the state to paused.
    function onTimerPause()
    {
        mTimerState = PAUSED;
    }

    //! The timer was restarted, so set the state to running again.
    function onTimerResume()
    {
        mTimerState = RUNNING;
    }

    //! The timer was reset, so reset all our tracking variables
    function onTimerReset()
    {
        mTimerState = STOPPED;
        mVal = mShowPace ? "0:00" : "0.00";
        mDists[0] = 0;
        mTimes[0] = 0;
        mOldest = 0;
        mCurrent = 0;
    }
  

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info) {
        // See Activity.Info in the documentation for available information.
		var Dist;
		var Time;
		var Rate; // User can choose pace or speed.

		// NB	info.elapsedTime is time since activity started
		//		info.timerTime is time timer has been running excluding pauses/stops
		//		shame there's no "timedDisance" :(

        if (mTimerState == RUNNING) {
        	if (info.timerTime == null || info.elapsedDistance == null) {
        		return mVal;
        	}
        	
        	mTimes[mCurrent] = info.timerTime;
        	mDists[mCurrent] = info.elapsedDistance;

       		Time = mTimes[mCurrent] - mTimes[mOldest];
        	Dist = mDists[mCurrent] - mDists[mOldest];
//  Set up mVal ready for display
        	if (mShowPace) {
	       		Rate = (Dist != 0) ? Time / Dist : 0.0;
		        var Mins = (Rate / 60).toNumber();
		        var Secs = Rate - (Mins * 60);
	    	    mVal = Lang.format("$1$:$2$", [Mins.format("%d"), Secs.format("%02d")]);
	       	} else {
	       		Rate = (Time != 0) ? Dist / Time * 1000 : 0.0;
	    	    mVal = Rate.format("%4.2f");	       		
	       	}

// The rest of the code is to set up the indexes ready for data in the next call
// If the distance is greater than we're interested in, keep discarding oldest values until it's OK
// but don't let the 'oldest' index "catch up and overtake" the 'current' one
			if (mUseDist) {
	        	while ((Dist - cDistAverageOver) > distAccuracy && mOldest != mCurrent) {
    	    		mOldest++;
        			if (mOldest >= bufLen) {
        				mOldest = 0;
        			}
		        	Dist = mDists[mCurrent] - mDists[mOldest];
    	    	}
			} else {
        		while ((Time - mTimeAverageOver) > timeAccuracy && mOldest != mCurrent) {
        			mOldest++;
        			if (mOldest >= bufLen) {
        				mOldest = 0;
        			}
		        	Time = mTimes[mCurrent] - mTimes[mOldest];
    	    	}
			}        	
// Move the 'current' index on and wrap around if necessary        	
       		mCurrent++;       		
       		if (mCurrent >= bufLen) {
       			mCurrent = 0;
       		}

// Has the 'current' index "caught up" with the oldest one?
// If so, move oldest on too (which discards the oldest time and distance)
// Don't forget to wrap around
			if (mCurrent == mOldest) {
       			mOldest++;
       			if (mOldest >= bufLen) {
        			mOldest = 0;
	        	}
        	}
        }
/* KISS - so comment out for now
        if (mTimerState == STOPPED) {
       		return mVal;
        } else if (mTimerState == PAUSED) {
    	  	return mVal;
    	}
*/
		return mVal;
    }

}