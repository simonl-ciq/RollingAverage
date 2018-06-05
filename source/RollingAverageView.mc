using Toybox.WatchUi as Ui;
using Toybox.Math;
using Toybox.System as Sys;
using Toybox.Application as App;
using Toybox.Application.Properties as Props;
//using Toybox.Test;

const cDistAverageOver = 200; // Distance (m) over which to average Rate
const distAccuracy = 2; // within how many metres ? or should it be a % ?

const cTimeAverageOver = 200; // Time (s) over which to average Rate
const timeAccuracy = 500; // within how many milli seconds ? or should it be a % ?

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

	hidden var mNotMetric = false;  // ie they are Sys.UNIT_METRIC by default

	hidden var mUseDist = true;
	hidden var mAverageOver = 100; // Distance (m) or Time (s) over which to average Rate
	hidden var mShowAsPace = true;

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
        var tAverageOver;
		var tDistTime;
		
        SimpleDataField.initialize();
        
        mTimes[0] = 0;
        mDists[0] = 0;
        label = "Roll. Avg.";

		mNotMetric = Sys.getDeviceSettings().paceUnits != Sys.UNIT_METRIC;

		if ( App has :Properties ) {
	        tDistTime = Props.getValue("distTime");
        	tAverageOver = Props.getValue("averageOver");
	        mShowAsPace = Props.getValue("showPace") == 1;
	    } else {
			var thisApp = App.getApp();
	        tDistTime = thisApp.getProperty("distTime");
	    	tAverageOver = thisApp.getProperty("averageOver");
	        mShowAsPace = thisApp.getProperty("showPace") == 1;
	    }

       	mUseDist = (tDistTime == null) ? cUseDist : (tDistTime == 0);

		if (mUseDist) {
	       	mAverageOver = (tAverageOver == null) ? cDistAverageOver : tAverageOver.toNumber();
		} else {
	       	mAverageOver = (tAverageOver == null) ? cTimeAverageOver : tAverageOver.toNumber() * 1000;
		}

        if (mShowAsPace == null) {
        	mShowAsPace = cShowPace;
        }
        mVal = mShowAsPace ? "0:00" : "0.00";
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
        mVal = mShowAsPace ? "0:00" : "0.00";
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
		var Rate; // User can choose pace or speed

		// NB	info.elapsedTime is time since activity started
		//		info.timerTime is time timer has been running excluding pauses/stops
		//		shame there's no "timedDistance" :(

        if (mTimerState == RUNNING) {
        	if (info.timerTime == null || info.elapsedDistance == null) {
        		return mVal;
        	}
        	
        	mTimes[mCurrent] = info.timerTime;
        	mDists[mCurrent] = info.elapsedDistance;

       		Time = mTimes[mCurrent] - mTimes[mOldest];
        	Dist = mDists[mCurrent] - mDists[mOldest];

//  Set up mVal ready for display
// Remember distance is metres, time is milliseconds
      		if (mNotMetric) {
       			Dist /= 1.609344; // km in a mile, near enough
       		}

            if (mShowAsPace) {
	       		Rate = (Dist != 0) ? Time / Dist : 0.0;
		        var Mins = (Rate / 60.0).toNumber();
		        var Secs = Rate - (Mins * 60);
	    	    mVal = Lang.format("$1$:$2$", [Mins.format("%d"), Secs.format("%02d")]);
	       	} else { // Show as Speed
	       		// & change from milli units (metres or "milli miles") per sec to full units (kilometres or miles) per hour
	       		Rate = (Time != 0) ? ((Dist * 1000 * 3.6) / Time) : 0.0;
	    	    mVal = Rate.format("%4.2f");	       		
	       	}

// The rest of the code is to set up the indexes ready for data in the next call
// If the distance is greater than we're interested in, keep discarding oldest values until it's OK
// but don't let the 'oldest' index "catch up and overtake" the 'current' one
			if (mUseDist) {
	        	while ((Dist - mAverageOver) > distAccuracy && mOldest != mCurrent) {
    	    		mOldest++;
        			if (mOldest >= bufLen) {
        				mOldest = 0;
        			}
		        	Dist = mDists[mCurrent] - mDists[mOldest];
    	    	}
			} else {
        		while ((Time - mAverageOver) > timeAccuracy && mOldest != mCurrent) {
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