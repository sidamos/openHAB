### FritzBox Call Monitor
Code and icons taken from https://community.openhab.org/t/fritzbox-call-overview/28430 (version by @vbier). CSS taken from https://community.openhab.org/t/custom-theme-in-habpanel-2-1-example/31100.
Thanks to the contributors of the thread and special thanks to @vbier.

Installation:
* configure default audio sink in openHAB (I am using a Google Home Mini, but you can also use the browser, where HABPanel is running)
* add a user in the FritzBox (configure FritzBox login to use user **and** password first)
* install the **FritzboxTR064 Binding** in openHAB and set user and password
* add the items and the rules
* copy **fritzbox.sh** and **lockRoutines** to some place (change BASEURL, USER, OPENHAB_DIR) and make them executable by the openHAB user
* change the path to **fritzbox.sh** in **fritzbox.rules**
* copy **fritzbox.svg**, **habpanel.css** and **habpanel-reload.js** to **conf/html**
* use **/static/habpanel.css** as "Additional stylesheet" in HABPanel config
* add a new Template Widget in HABPanel using **fritzbox.template**
* receive one call to initialize everything
