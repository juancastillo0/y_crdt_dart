import 'package:flutter/material.dart';
import 'package:y_crdt/y_crdt.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class WebRtcDemoController {
  final ydoc = Doc();
  late final WebrtcProvider provider;

  late final YArray<String> todos = ydoc.getArray<String>('todos');

  WebRtcDemoController() {
    provider = WebrtcProvider(
      'your-room-name',
      ydoc,
      signaling: ['ws://localhost:4040'],
    );
  }

  void addTodo(String todo) {
    todos.push([todo]);
  }

  void removeTodo(int index) {
    todos.delete(index);
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  final textController = TextEditingController();
  final webrtcController = WebRtcDemoController();

  final changes = <YArrayEvent<String>>[];

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  void initState() {
    super.initState();
    webrtcController.todos.observe((event, transaction) {
      changes.add(event);
      setState(() {});
    });
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              height: 300,
              width: 600,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        ...changes.map(
                          (element) => Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(element.changes.toString()),
                          ),
                        )
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: webrtcController.todos.length,
                      itemBuilder: (context, index) {
                        final todo = webrtcController.todos.get(index);
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(child: Text('$index. $todo')),
                              TextButton(
                                onPressed: () {
                                  webrtcController.removeTodo(index);
                                },
                                child: const Text("DELETE"),
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 300,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      final text = textController.text.trim();
                      if (text.isNotEmpty) {
                        webrtcController.addTodo(text);
                        textController.clear();
                      }
                    },
                    child: const Text('ADD'),
                  ),
                ],
              ),
            ),
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
