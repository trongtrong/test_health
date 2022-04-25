import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';

void main() => runApp(HealthApp());

class HealthApp extends StatefulWidget {
  @override
  _HealthAppState createState() => _HealthAppState();
}

enum AppState {
  DATA_NOT_FETCHED,
  FETCHING_DATA,
  DATA_READY,
  NO_DATA,
  AUTH_NOT_GRANTED,
  DATA_ADDED,
  DATA_NOT_ADDED,
  STEPS_READY,
}

class _HealthAppState extends State<HealthApp> {
  List<HealthDataPoint> _healthDataList = [];
  LinkedHashMap linkedHashMap = LinkedHashMap<String, StepByDay>();
  AppState _state = AppState.DATA_NOT_FETCHED;
  int _nofSteps = 10;
  double _mgdl = 10.0;

  // create a HealthFactory for use in the app
  HealthFactory health = HealthFactory();

  /// Fetch data points from the health plugin and show them in the app.
  Future fetchData() async {
    setState(() => _state = AppState.FETCHING_DATA);

    // define the types to get
    final types = [
      HealthDataType.STEPS,
      // Uncomment this line on iOS - only available on iOS
      // HealthDataType.DISTANCE_WALKING_RUNNING,
    ];

    // with coresponsing permissions
    final permissions = [
      HealthDataAccess.READ,
    ];

    // get data within the last 24 hours
    final now = DateTime.now();
    final sixDayAgo = now.subtract(Duration(days: 6));

    print('now ==   ${now.toString()}');
    print('now ==   ${sixDayAgo.toString()}');

    // requesting access to the data types before reading them
    // note that strictly speaking, the [permissions] are not
    // needed, since we only want READ access.
    bool requested = await health.requestAuthorization(types, permissions: permissions);

    if (requested) {
      try {
        // fetch health data
        List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(sixDayAgo, now, types);

        // save all the new data points (only the first 100)
        _healthDataList.addAll((healthData.length < 100) ? healthData : healthData.sublist(0, 100));
      } catch (error) {
        print("Exception in getHealthDataFromTypes: $error");
      }

      // filter out duplicates
      _healthDataList = HealthFactory.removeDuplicates(_healthDataList);

      // print the results
      _healthDataList.forEach((x) {
        //format theo định dạng năm-tháng-ngày
        DateTime format = x.dateFrom;
        String formattedDate = DateFormat('yyyy-MM-dd').format(format);

        //formattedDate ở đây là key, sẽ dựa vào nó để group những giá trị mà health trả về
        if (linkedHashMap.containsKey(formattedDate)) {
          //lấy ra Object mà chứa cái key đó
          StepByDay stepByDay = linkedHashMap[formattedDate];
          //cộng dồn giá trị
          stepByDay.step += x.value;
          //save lại bằng cách put nó vào map
          linkedHashMap.putIfAbsent(formattedDate, () => stepByDay);
        } else {
          //nếu chưa có key tuwogn ứng, ta thêm nó vào map với giá trị là số bước mà phần tử x tả về
          linkedHashMap.putIfAbsent(formattedDate, () => StepByDay(step: x.value));
        }

      });

      linkedHashMap.forEach((key, value) {
        print('key ==  ${key} ------      value ==   ${value.step}');
      });

      // update the UI to display the results
      setState(() {
        _state = _healthDataList.isEmpty ? AppState.NO_DATA : AppState.DATA_READY;
      });
    } else {
      print("Authorization not granted");
      setState(() => _state = AppState.DATA_NOT_FETCHED);
    }
  }

  /// Add some random health data.
  Future addData() async {
    final now = DateTime.now();
    final earlier = now.subtract(Duration(minutes: 5));

    _nofSteps = Random().nextInt(10);
    final types = [HealthDataType.STEPS, HealthDataType.BLOOD_GLUCOSE];
    final rights = [HealthDataAccess.WRITE, HealthDataAccess.WRITE];
    final permissions = [HealthDataAccess.READ_WRITE, HealthDataAccess.READ_WRITE];
    bool? hasPermissions = await HealthFactory.hasPermissions(types, permissions: rights);
    if (hasPermissions == false) {
      await health.requestAuthorization(types, permissions: permissions);
    }

    _mgdl = Random().nextInt(10) * 1.0;
    bool success = await health.writeHealthData(_nofSteps.toDouble(), HealthDataType.STEPS, earlier, now);

    if (success) {
      success = await health.writeHealthData(_mgdl, HealthDataType.BLOOD_GLUCOSE, now, now);
    }

    setState(() {
      _state = success ? AppState.DATA_ADDED : AppState.DATA_NOT_ADDED;
    });
  }

  /// Fetch steps from the health plugin and show them in the app.
  Future fetchStepData() async {
    int? steps;

    // get steps for today (i.e., since midnight)
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    bool requested = await health.requestAuthorization([HealthDataType.STEPS]);

    print('requested ==   ${requested}');

    if (requested) {
      try {
        steps = await health.getTotalStepsInInterval(midnight, now);
      } catch (error) {
        print("Caught exception in getTotalStepsInInterval: $error");
      }

      print('Total number of steps: $steps');

      setState(() {
        _nofSteps = (steps == null) ? 0 : steps;
        _state = (steps == null) ? AppState.NO_DATA : AppState.STEPS_READY;
      });
    } else {
      print("Authorization not granted");
      setState(() => _state = AppState.DATA_NOT_FETCHED);
    }
  }

  Widget _contentFetchingData() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(
              strokeWidth: 10,
            )),
        Text('Fetching data...')
      ],
    );
  }

  Widget _contentDataReady() {
    return ListView.builder(
        itemCount: linkedHashMap.length,
        itemBuilder: (_, index) {
          // HealthDataPoint p = _healthDataList[index];
          String key = linkedHashMap.keys.elementAt(index);
          StepByDay step = linkedHashMap[key];
          return ListTile(
            title: Text("${key}: ${step.step}"),
          );
        });
  }

  Widget _contentNoData() {
    return Text('No Data to show');
  }

  Widget _contentNotFetched() {
    return Column(
      children: [
        Text('Press the download button to fetch data.'),
        Text('Press the plus button to insert some random data.'),
        Text('Press the walking button to get total step count.'),
      ],
      mainAxisAlignment: MainAxisAlignment.center,
    );
  }

  Widget _authorizationNotGranted() {
    return Text('Authorization not given. '
        'For Android please check your OAUTH2 client ID is correct in Google Developer Console. '
        'For iOS check your permissions in Apple Health.');
  }

  Widget _dataAdded() {
    return Text('$_nofSteps steps and $_mgdl mgdl are inserted successfully!');
  }

  Widget _stepsFetched() {
    return Text('Total number of steps: $_nofSteps');
  }

  Widget _dataNotAdded() {
    return Text('Failed to add data');
  }

  Widget _content() {
    if (_state == AppState.DATA_READY)
      return _contentDataReady();
    else if (_state == AppState.NO_DATA)
      return _contentNoData();
    else if (_state == AppState.FETCHING_DATA)
      return _contentFetchingData();
    else if (_state == AppState.AUTH_NOT_GRANTED)
      return _authorizationNotGranted();
    else if (_state == AppState.DATA_ADDED)
      return _dataAdded();
    else if (_state == AppState.STEPS_READY)
      return _stepsFetched();
    else if (_state == AppState.DATA_NOT_ADDED) return _dataNotAdded();

    return _contentNotFetched();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            title: const Text('Health Example'),
            actions: <Widget>[
              IconButton(
                icon: Icon(Icons.file_download),
                onPressed: () {
                  fetchData();
                },
              ),
              IconButton(
                onPressed: () {
                  addData();
                },
                icon: Icon(Icons.add),
              ),
              IconButton(
                onPressed: () {
                  fetchStepData();
                },
                icon: Icon(Icons.nordic_walking),
              )
            ],
          ),
          body: Center(
            child: _content(),
          )),
    );
  }
}

class StepByDay {
  num step;
  //cần thêm field nào thì có thể viết thêm

  StepByDay({this.step = 0});
}
