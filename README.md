# testapp-threepilars-UWL
I use this to demonstrate collecting metrics, logs and traces on Openshift - Using Openshift data foundation managed noobaa as the storage backend.

User workload monitoring is used to store user metrics.
The cluster logging and loki operators are used to collect and store logs.
The Opentelemetry collector is used to collect traces.
Tempo is used to store traces. 
The cluster observability operator manages the UIPlugins.  

testapps are deployed in namespaces `ns1-uwl` and `ns2-uwl`

The app in `ns1-uwl`: 
 - https://github.com/coffeegoesincodecomesout/testapp-ThreePilars 

The app in `ns2-uwl`: 
 - https://github.com/coffeegoesincodecomesout/testapp-ThreePilars-Frontend 
 - https://github.com/coffeegoesincodecomesout/testapp-ThreePilars-backend 

Run the Deploy script:

```
./00_Deploy.sh
```
