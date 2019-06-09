using Toybox.WatchUi as Ui;
using Toybox.Math;
using Toybox.System as Sys;
using Toybox.Application as App;
using Toybox.Application.Properties as Props;
//using Toybox.Test;

const cDistAverageOver = 200.0; // Distance (m) over which to average Rate
const distAccuracy = 2; // within how many metres ? or should it be a % ?

const cTimeAverageOver = 60; // Time (s) over which to average Rate
const timeAccuracy = 1000; // within how many milli seconds ? or should it be a % ?

const bufLen = 600; // max number of points

const cShowPace = true;
const cUseDist = true;

const KM_PER_MILE = 1.609344; // km in a mile
const METRES_PER_MILE = 1609.344; // metres in a mile
//const MILES_PER_METER = 0.000621371; // Reciprocal of above
const METRES_PER_YARD = 0.9144;

class RollingAverageView extends Ui.SimpleDataField {

    enum
    {
        OFF,
        STOPPED,
        PAUSED,
        RUNNING
    }

	hidden var mNotMetricPace = false;  // ie they are Sys.UNIT_METRIC by default
	hidden var mNotMetricDist = false;  // ie they are Sys.UNIT_METRIC by default

	hidden var mUseDist = true;
	hidden var mAverageOver = 100; // Distance (m) or Time (s) over which to average Rate
	hidden var mShowAsPace = true;

    hidden var mTimerState = OFF;

	hidden var mTimes = new [bufLen];
	hidden var mDists = new [bufLen];

    hidden var mOldest  = 0;
    hidden var mCurrent = 0;

    hidden var mSlow = false; // true do compute every "Mod" calls, false do it every time
    hidden var mMod = 1; // a toggle
    hidden var mDoCompute = 0; // a toggle

    hidden var mNotAvailable = false;
    hidden var mVal	  = "";

    // Set the label of the data field here.
    function initialize() {
        var tAverageOver;
        var tfAverageOver;
		var tDistTime;
		var tUnits;
		var tiAverageOver;
		
        SimpleDataField.initialize();
        
        mTimes[0] = 0;
        mDists[0] = 0;

		mNotMetricPace = Sys.getDeviceSettings().paceUnits != Sys.UNIT_METRIC;
		mNotMetricDist = Sys.getDeviceSettings().distanceUnits != Sys.UNIT_METRIC;

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
			if (tAverageOver == null) {
				tAverageOver = cDistAverageOver;
			}
			tfAverageOver = tAverageOver.toFloat();
		    tiAverageOver = tAverageOver.toNumber();
			if (mNotMetricDist) {
// work out display title & convert yards/miles to metres
				if (tiAverageOver > 3) {
// Big number means small units i.e. yards not miles
		    	    tUnits = tiAverageOver.toString() + " yard";
					tfAverageOver *= METRES_PER_YARD;
//					mSlow = false;
				} else {
// Small number means big units i.e. miles not yards
					if (tfAverageOver == tiAverageOver) {
// An integer number of miles
		    	    	tUnits = tiAverageOver.toString() + " mile";
		    	    } else {
		    	    	tUnits = tfAverageOver.format("%4.2f") + " mile";
		    	    }
					tfAverageOver *= METRES_PER_MILE;
//					mSlow = true;
				}
				tiAverageOver = tfAverageOver.toNumber();
			} else {
// work out display title & maybe convert km to metres
				if (tiAverageOver > 5) {
// Big number means small units i.e. metres not km
		    	    tUnits = tiAverageOver.toString() + " metre";
//					mSlow = false;
				} else {
// Small number means big units i.e. km not metres
					if (tfAverageOver == tiAverageOver) {
// An integer number of km					
		    	    	tUnits = tiAverageOver.toString() + " km";
		    	    } else {
		    	    	tUnits = tfAverageOver.format("%4.2f") + " km";
		    	    }
					tfAverageOver *= 1000.0;
//					mSlow = true;
				}
				tiAverageOver = tfAverageOver.toNumber();
			}
			mAverageOver = tiAverageOver;
		} else {
		    tiAverageOver = (tAverageOver == null) ? cTimeAverageOver : tAverageOver.toNumber();
			tUnits = tiAverageOver.toString() + " secs";
//			mSlow = false;
			mAverageOver = tiAverageOver * 1000;
		}
			if (mAverageOver > bufLen) {
				mSlow = true;
				mMod = Math.round(((mAverageOver.toFloat() / bufLen)+0.5).toNumber()) + 1;
			} else {
				mSlow = false;
			}

		if (mShowAsPace == null) {
			mShowAsPace = cShowPace;
		}

		label = tUnits + (mShowAsPace ? " Pace" : " Speed");

		var info = Activity.getActivityInfo();
       	if (!(info has :timerTime) || !(info has :elapsedDistance)) {
       		mNotAvailable = true;
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
		var rawDist;
		var Dist;
		var Time;
		var Rate; // User can choose pace or speed

       	if (mNotAvailable) {
       		return "Not Available";
       	}

		// NB	info.elapsedTime is time since activity started
		//		info.timerTime is time timer has been running excluding pauses/stops
		//		shame there's no "timedDistance" :(
        if (mTimerState == RUNNING) {
        	if (info.timerTime == null || info.elapsedDistance == null) {
        		return mVal;
        	}

        	if (mSlow) {
        		mDoCompute = (mDoCompute+1) % mMod;
        		if (mDoCompute != 1) {
        			return mVal;
        		}
        	}
        	
        	mTimes[mCurrent] = info.timerTime;
        	mDists[mCurrent] = info.elapsedDistance;
        	rawDist = mDists[mCurrent] - mDists[mOldest];

// Look for the distance nearest to the value we're averaging over
			if (mUseDist && mCurrent > 0) {
				var ind = mOldest;
				var rawDist1 = rawDist;
				var diff1 = (rawDist - mAverageOver).abs();
				var diff0 = diff1;
				while (diff1 <= diff0) {
					diff0 = diff1;
					mOldest = ind;
					rawDist = rawDist1;
					ind++;
        			if (ind >= bufLen) {
        				ind = 0;
        			}
        			if (ind == mCurrent) {
        				break;
        			}
					rawDist1 = mDists[mCurrent] - mDists[ind];
					diff1 = (rawDist1 - mAverageOver).abs();
				}
			}
       		Time = mTimes[mCurrent] - mTimes[mOldest];
//Sys.println(mCurrent + ", " + mOldest + ", "  + rawDist + ", " + Time);

//  Set up mVal ready for display
// Remember distance is metres, time is milliseconds
			Dist = (mNotMetricPace) ? rawDist / KM_PER_MILE : rawDist;
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
	        	while (rawDist > mAverageOver && mOldest != mCurrent) {
    	    		mOldest++;
        			if (mOldest >= bufLen) {
        				mOldest = 0;
        			}
		        	rawDist = mDists[mCurrent] - mDists[mOldest];
    	    	}
			} else {
        		while (Time > mAverageOver && mOldest != mCurrent) {
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
		return mVal;
    }

}