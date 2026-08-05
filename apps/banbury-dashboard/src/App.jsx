import { useState, useMemo, useCallback } from "react";
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ReferenceLine, ResponsiveContainer } from "recharts";
import Papa from "papaparse";
import { Upload, FileWarning, AlertTriangle, ChevronLeft, LayoutGrid, GitMerge } from "lucide-react";

// Embedded demo sample: 450 readings from 2026/06/06, Banbury Q1 side.
// Spans two formulas (39Q1, TC16Q) and both auto/manual modes, so filters have
// something real to filter on. Upload a real CSV to replace this.
const SAMPLE_ROWS =
[{"time":"00:59:57","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":337.0,"rpm":30.0,"temp":91.0,"pressure":6.0},{"time":"01:00:02","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":233.0,"rpm":30.0,"temp":0.0,"pressure":11.0},{"time":"01:00:07","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":173.0,"rpm":30.0,"temp":3.0,"pressure":25.0},{"time":"01:00:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":202.0,"rpm":30.0,"temp":95.0,"pressure":25.0},{"time":"01:00:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":166.0,"rpm":30.0,"temp":93.0,"pressure":25.0},{"time":"01:00:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":224.0,"rpm":30.0,"temp":95.0,"pressure":14.0},{"time":"01:00:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":251.0,"rpm":30.0,"temp":94.0,"pressure":23.0},{"time":"01:00:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":297.0,"rpm":30.0,"temp":96.0,"pressure":26.0},{"time":"01:00:42","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":307.0,"rpm":30.0,"temp":97.0,"pressure":34.0},{"time":"01:00:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":309.0,"rpm":30.0,"temp":99.0,"pressure":35.0},{"time":"01:00:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":304.0,"rpm":30.0,"temp":99.0,"pressure":64.0},{"time":"01:00:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":220.0,"rpm":30.0,"temp":101.0,"pressure":35.0},{"time":"01:01:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":156.0,"rpm":25.0,"temp":101.0,"pressure":25.0},{"time":"01:01:12","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":173.0,"rpm":25.0,"temp":100.0,"pressure":30.0},{"time":"01:01:17","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":272.0,"rpm":25.0,"temp":103.0,"pressure":31.0},{"time":"01:01:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":266.0,"rpm":25.0,"temp":105.0,"pressure":38.0},{"time":"01:01:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":284.0,"rpm":25.0,"temp":107.0,"pressure":44.0},{"time":"01:01:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":281.0,"rpm":25.0,"temp":109.0,"pressure":27.0},{"time":"01:01:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":280.0,"rpm":25.0,"temp":110.0,"pressure":30.0},{"time":"01:01:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":275.0,"rpm":25.0,"temp":112.0,"pressure":45.0},{"time":"01:01:52","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":273.0,"rpm":25.0,"temp":115.0,"pressure":33.0},{"time":"01:01:57","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":267.0,"rpm":25.0,"temp":116.0,"pressure":33.0},{"time":"01:02:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":273.0,"rpm":25.0,"temp":119.0,"pressure":32.0},{"time":"01:02:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":265.0,"rpm":25.0,"temp":120.0,"pressure":36.0},{"time":"01:02:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":269.0,"rpm":25.0,"temp":122.0,"pressure":34.0},{"time":"01:02:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":263.0,"rpm":25.0,"temp":122.0,"pressure":31.0},{"time":"01:02:27","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":262.0,"rpm":25.0,"temp":126.0,"pressure":41.0},{"time":"01:02:32","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":258.0,"rpm":25.0,"temp":127.0,"pressure":25.0},{"time":"01:02:37","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":25.0,"current":169.0,"rpm":25.0,"temp":128.0,"pressure":23.0},{"time":"01:05:22","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":76.0,"pressure":41.0},{"time":"01:05:27","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":75.0,"pressure":32.0},{"time":"01:05:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":75.0,"pressure":29.0},{"time":"01:05:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":74.0,"pressure":27.0},{"time":"01:05:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":74.0,"pressure":26.0},{"time":"01:05:52","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":72.0,"pressure":23.0},{"time":"01:05:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":72.0,"pressure":22.0},{"time":"01:06:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":71.0,"pressure":20.0},{"time":"01:06:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":71.0,"pressure":20.0},{"time":"01:06:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":70.0,"pressure":19.0},{"time":"01:06:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":70.0,"pressure":8.0},{"time":"01:06:27","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":69.0,"pressure":24.0},{"time":"01:06:32","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":69.0,"pressure":24.0},{"time":"01:06:37","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":68.0,"pressure":24.0},{"time":"01:06:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":68.0,"pressure":24.0},{"time":"01:06:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":68.0,"pressure":24.0},{"time":"01:06:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":68.0,"pressure":24.0},{"time":"01:06:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":67.0,"pressure":24.0},{"time":"01:07:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":67.0,"pressure":24.0},{"time":"01:07:12","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":66.0,"pressure":70.0},{"time":"01:07:17","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":66.0,"pressure":53.0},{"time":"01:07:22","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":66.0,"pressure":8.0},{"time":"01:07:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":65.0,"pressure":57.0},{"time":"01:07:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":65.0,"pressure":17.0},{"time":"01:07:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":65.0,"pressure":11.0},{"time":"01:07:47","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":64.0,"pressure":10.0},{"time":"01:07:52","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":64.0,"pressure":9.0},{"time":"01:07:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":64.0,"pressure":10.0},{"time":"01:08:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":64.0,"pressure":9.0},{"time":"01:08:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":63.0,"pressure":10.0},{"time":"01:08:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":63.0,"pressure":10.0},{"time":"01:08:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":63.0,"pressure":9.0},{"time":"01:08:27","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":63.0,"pressure":26.0},{"time":"01:08:32","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":62.0,"pressure":8.0},{"time":"01:08:37","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":62.0,"pressure":6.0},{"time":"01:08:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":62.0,"pressure":22.0},{"time":"01:08:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":62.0,"pressure":32.0},{"time":"01:08:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":61.0,"pressure":47.0},{"time":"01:08:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":61.0,"pressure":15.0},{"time":"01:09:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":61.0,"pressure":11.0},{"time":"01:09:12","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":60.0,"pressure":8.0},{"time":"01:09:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":60.0,"pressure":16.0},{"time":"01:09:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":60.0,"pressure":10.0},{"time":"01:09:32","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":60.0,"pressure":10.0},{"time":"01:09:37","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":59.0,"pressure":28.0},{"time":"01:09:42","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":0.0,"temp":59.0,"pressure":65.0},{"time":"01:09:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":0.0,"rpm":3.0,"temp":58.0,"pressure":21.0},{"time":"01:09:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":84.0,"rpm":11.0,"temp":59.0,"pressure":14.0},{"time":"01:09:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":108.0,"rpm":19.0,"temp":58.0,"pressure":13.0},{"time":"01:10:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":112.0,"rpm":28.0,"temp":58.0,"pressure":13.0},{"time":"01:10:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":109.0,"rpm":30.0,"temp":58.0,"pressure":12.0},{"time":"01:10:17","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":151.0,"rpm":30.0,"temp":72.0,"pressure":11.0},{"time":"01:10:22","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":167.0,"rpm":30.0,"temp":82.0,"pressure":11.0},{"time":"01:10:27","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":189.0,"rpm":30.0,"temp":83.0,"pressure":12.0},{"time":"01:10:32","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":198.0,"rpm":30.0,"temp":87.0,"pressure":11.0},{"time":"01:10:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":246.0,"rpm":30.0,"temp":91.0,"pressure":11.0},{"time":"01:10:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":274.0,"rpm":30.0,"temp":94.0,"pressure":11.0},{"time":"01:10:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":262.0,"rpm":30.0,"temp":95.0,"pressure":11.0},{"time":"01:10:57","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":277.0,"rpm":30.0,"temp":98.0,"pressure":10.0},{"time":"01:11:02","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":230.0,"rpm":30.0,"temp":94.0,"pressure":32.0},{"time":"01:11:07","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":244.0,"rpm":30.0,"temp":100.0,"pressure":25.0},{"time":"01:11:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":193.0,"rpm":30.0,"temp":97.0,"pressure":24.0},{"time":"01:11:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":188.0,"rpm":30.0,"temp":99.0,"pressure":13.0},{"time":"01:11:27","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":288.0,"rpm":30.0,"temp":97.0,"pressure":33.0},{"time":"01:11:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":292.0,"rpm":30.0,"temp":97.0,"pressure":40.0},{"time":"01:11:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":306.0,"rpm":30.0,"temp":99.0,"pressure":37.0},{"time":"01:11:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":311.0,"rpm":30.0,"temp":99.0,"pressure":35.0},{"time":"01:11:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":302.0,"rpm":30.0,"temp":102.0,"pressure":20.0},{"time":"01:11:57","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":198.0,"rpm":29.0,"temp":103.0,"pressure":10.0},{"time":"01:12:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":175.0,"rpm":25.0,"temp":104.0,"pressure":25.0},{"time":"01:12:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":185.0,"rpm":25.0,"temp":104.0,"pressure":32.0},{"time":"01:12:17","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":270.0,"rpm":25.0,"temp":108.0,"pressure":30.0},{"time":"01:12:22","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":282.0,"rpm":25.0,"temp":108.0,"pressure":42.0},{"time":"01:12:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":285.0,"rpm":25.0,"temp":111.0,"pressure":31.0},{"time":"01:12:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":276.0,"rpm":25.0,"temp":111.0,"pressure":34.0},{"time":"01:12:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":281.0,"rpm":25.0,"temp":114.0,"pressure":37.0},{"time":"01:12:47","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":278.0,"rpm":25.0,"temp":117.0,"pressure":35.0},{"time":"01:12:52","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":273.0,"rpm":25.0,"temp":119.0,"pressure":45.0},{"time":"01:12:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":271.0,"rpm":25.0,"temp":120.0,"pressure":29.0},{"time":"01:13:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":270.0,"rpm":25.0,"temp":122.0,"pressure":37.0},{"time":"01:13:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":263.0,"rpm":25.0,"temp":124.0,"pressure":39.0},{"time":"01:13:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":258.0,"rpm":25.0,"temp":125.0,"pressure":25.0},{"time":"01:13:22","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":250.0,"rpm":25.0,"temp":128.0,"pressure":27.0},{"time":"01:13:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":176.0,"rpm":24.0,"temp":128.0,"pressure":61.0},{"time":"01:13:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":167.0,"rpm":24.0,"temp":127.0,"pressure":38.0},{"time":"01:13:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":130.0,"rpm":24.0,"temp":128.0,"pressure":33.0},{"time":"01:13:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":2,"batch":28.0,"current":157.0,"rpm":24.0,"temp":130.0,"pressure":22.0},{"time":"01:13:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":114.0,"rpm":19.0,"temp":122.0,"pressure":73.0},{"time":"01:13:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":101.0,"rpm":2.0,"temp":117.0,"pressure":75.0},{"time":"01:13:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":0.0,"pressure":77.0},{"time":"01:14:07","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":1.0,"pressure":57.0},{"time":"01:14:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":104.0,"pressure":25.0},{"time":"01:14:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":102.0,"pressure":21.0},{"time":"01:14:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":100.0,"pressure":20.0},{"time":"01:14:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":98.0,"pressure":18.0},{"time":"01:14:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":96.0,"pressure":19.0},{"time":"01:14:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":95.0,"pressure":17.0},{"time":"01:14:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":93.0,"pressure":17.0},{"time":"01:14:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":92.0,"pressure":16.0},{"time":"01:14:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":90.0,"pressure":15.0},{"time":"01:15:02","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":88.0,"pressure":14.0},{"time":"01:15:07","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":87.0,"pressure":14.0},{"time":"01:15:12","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":86.0,"pressure":19.0},{"time":"01:15:17","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":85.0,"pressure":63.0},{"time":"01:15:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":45.0,"rpm":8.0,"temp":84.0,"pressure":18.0},{"time":"01:15:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":111.0,"rpm":16.0,"temp":83.0,"pressure":11.0},{"time":"01:15:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":120.0,"rpm":24.0,"temp":82.0,"pressure":10.0},{"time":"01:15:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":110.0,"rpm":24.0,"temp":82.0,"pressure":10.0},{"time":"01:15:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":109.0,"rpm":24.0,"temp":81.0,"pressure":10.0},{"time":"01:15:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":109.0,"rpm":24.0,"temp":80.0,"pressure":11.0},{"time":"01:15:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":107.0,"rpm":24.0,"temp":79.0,"pressure":11.0},{"time":"01:16:02","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":106.0,"rpm":24.0,"temp":78.0,"pressure":10.0},{"time":"01:16:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":106.0,"rpm":24.0,"temp":77.0,"pressure":11.0},{"time":"01:16:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":106.0,"rpm":24.0,"temp":76.0,"pressure":11.0},{"time":"01:16:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":106.0,"rpm":24.0,"temp":76.0,"pressure":11.0},{"time":"01:16:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":106.0,"rpm":24.0,"temp":75.0,"pressure":9.0},{"time":"01:16:32","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":105.0,"rpm":7.0,"temp":74.0,"pressure":9.0},{"time":"01:16:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":30.0,"rpm":0.0,"temp":74.0,"pressure":8.0},{"time":"01:16:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":73.0,"pressure":68.0},{"time":"01:16:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":72.0,"pressure":60.0},{"time":"01:16:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":72.0,"pressure":56.0},{"time":"01:16:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":71.0,"pressure":33.0},{"time":"01:17:07","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":70.0,"pressure":28.0},{"time":"01:17:12","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":70.0,"pressure":26.0},{"time":"01:17:17","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":69.0,"pressure":25.0},{"time":"01:17:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":68.0,"pressure":23.0},{"time":"01:17:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":68.0,"pressure":23.0},{"time":"01:17:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":68.0,"pressure":21.0},{"time":"01:17:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":67.0,"pressure":20.0},{"time":"01:17:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":67.0,"pressure":20.0},{"time":"01:17:52","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":66.0,"pressure":18.0},{"time":"01:17:57","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":66.0,"pressure":17.0},{"time":"01:18:02","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":66.0,"pressure":16.0},{"time":"01:18:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":65.0,"pressure":15.0},{"time":"01:18:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":65.0,"pressure":15.0},{"time":"01:18:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":65.0,"pressure":14.0},{"time":"01:18:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":65.0,"pressure":14.0},{"time":"01:18:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":64.0,"pressure":13.0},{"time":"01:18:37","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":64.0,"pressure":13.0},{"time":"01:18:42","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":63.0,"pressure":12.0},{"time":"01:18:47","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":63.0,"pressure":12.0},{"time":"01:18:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":63.0,"pressure":11.0},{"time":"01:18:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":63.0,"pressure":11.0},{"time":"01:19:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":0.0,"rpm":0.0,"temp":62.0,"pressure":12.0},{"time":"01:19:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":69.0,"rpm":8.0,"temp":62.0,"pressure":11.0},{"time":"01:19:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":107.0,"rpm":17.0,"temp":62.0,"pressure":12.0},{"time":"01:19:22","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":111.0,"rpm":30.0,"temp":61.0,"pressure":12.0},{"time":"01:19:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":122.0,"rpm":30.0,"temp":62.0,"pressure":12.0},{"time":"01:19:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":131.0,"rpm":30.0,"temp":70.0,"pressure":11.0},{"time":"01:19:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":163.0,"rpm":30.0,"temp":71.0,"pressure":11.0},{"time":"01:19:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":199.0,"rpm":30.0,"temp":79.0,"pressure":11.0},{"time":"01:19:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":191.0,"rpm":30.0,"temp":85.0,"pressure":11.0},{"time":"01:19:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":178.0,"rpm":30.0,"temp":91.0,"pressure":11.0},{"time":"01:19:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":253.0,"rpm":30.0,"temp":94.0,"pressure":10.0},{"time":"01:20:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":226.0,"rpm":30.0,"temp":96.0,"pressure":10.0},{"time":"01:20:12","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":189.0,"rpm":30.0,"temp":94.0,"pressure":9.0},{"time":"01:20:17","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":182.0,"rpm":30.0,"temp":93.0,"pressure":34.0},{"time":"01:20:22","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":233.0,"rpm":30.0,"temp":91.0,"pressure":25.0},{"time":"01:20:27","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":187.0,"rpm":30.0,"temp":97.0,"pressure":25.0},{"time":"01:20:32","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":210.0,"rpm":30.0,"temp":95.0,"pressure":12.0},{"time":"01:20:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":205.0,"rpm":30.0,"temp":97.0,"pressure":28.0},{"time":"01:20:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":320.0,"rpm":30.0,"temp":97.0,"pressure":41.0},{"time":"01:20:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":304.0,"rpm":30.0,"temp":99.0,"pressure":38.0},{"time":"01:20:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":304.0,"rpm":30.0,"temp":99.0,"pressure":37.0},{"time":"01:21:02","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":306.0,"rpm":30.0,"temp":102.0,"pressure":46.0},{"time":"01:21:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":286.0,"rpm":30.0,"temp":103.0,"pressure":22.0},{"time":"01:21:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":202.0,"rpm":28.0,"temp":104.0,"pressure":9.0},{"time":"01:21:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":180.0,"rpm":25.0,"temp":104.0,"pressure":25.0},{"time":"01:21:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":160.0,"rpm":25.0,"temp":105.0,"pressure":25.0},{"time":"01:21:32","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":281.0,"rpm":25.0,"temp":108.0,"pressure":29.0},{"time":"01:21:37","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":277.0,"rpm":25.0,"temp":110.0,"pressure":36.0},{"time":"01:21:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":282.0,"rpm":25.0,"temp":111.0,"pressure":42.0},{"time":"01:21:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":286.0,"rpm":25.0,"temp":113.0,"pressure":29.0},{"time":"01:21:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":276.0,"rpm":25.0,"temp":113.0,"pressure":40.0},{"time":"01:22:02","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":270.0,"rpm":25.0,"temp":116.0,"pressure":33.0},{"time":"01:22:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":276.0,"rpm":25.0,"temp":119.0,"pressure":38.0},{"time":"01:22:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":273.0,"rpm":25.0,"temp":121.0,"pressure":37.0},{"time":"01:22:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":272.0,"rpm":25.0,"temp":122.0,"pressure":46.0},{"time":"01:22:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":267.0,"rpm":25.0,"temp":124.0,"pressure":30.0},{"time":"01:22:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":263.0,"rpm":25.0,"temp":126.0,"pressure":29.0},{"time":"01:22:37","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":28.0,"current":172.0,"rpm":25.0,"temp":127.0,"pressure":23.0},{"time":"01:31:10","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":125.0,"rpm":30.0,"temp":90.0,"pressure":8.0},{"time":"01:31:15","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":199.0,"rpm":30.0,"temp":93.0,"pressure":25.0},{"time":"01:31:21","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":168.0,"rpm":30.0,"temp":94.0,"pressure":25.0},{"time":"01:31:26","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":245.0,"rpm":30.0,"temp":94.0,"pressure":24.0},{"time":"01:31:31","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":209.0,"rpm":30.0,"temp":94.0,"pressure":12.0},{"time":"01:31:36","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":280.0,"rpm":30.0,"temp":94.0,"pressure":26.0},{"time":"01:31:41","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":299.0,"rpm":30.0,"temp":97.0,"pressure":24.0},{"time":"01:31:46","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":299.0,"rpm":30.0,"temp":98.0,"pressure":34.0},{"time":"01:31:55","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":299.0,"rpm":30.0,"temp":100.0,"pressure":36.0},{"time":"01:32:00","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":300.0,"rpm":30.0,"temp":102.0,"pressure":26.0},{"time":"01:32:05","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":268.0,"rpm":30.0,"temp":104.0,"pressure":52.0},{"time":"01:32:11","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":159.0,"rpm":25.0,"temp":103.0,"pressure":31.0},{"time":"01:32:16","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":171.0,"rpm":25.0,"temp":104.0,"pressure":10.0},{"time":"01:32:25","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":270.0,"rpm":25.0,"temp":107.0,"pressure":28.0},{"time":"01:32:30","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":267.0,"rpm":25.0,"temp":109.0,"pressure":40.0},{"time":"01:32:36","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":285.0,"rpm":25.0,"temp":110.0,"pressure":46.0},{"time":"01:32:41","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":283.0,"rpm":25.0,"temp":112.0,"pressure":26.0},{"time":"01:32:46","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":273.0,"rpm":25.0,"temp":114.0,"pressure":34.0},{"time":"01:32:51","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":270.0,"rpm":25.0,"temp":116.0,"pressure":46.0},{"time":"01:33:00","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":268.0,"rpm":25.0,"temp":118.0,"pressure":34.0},{"time":"01:33:05","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":260.0,"rpm":25.0,"temp":120.0,"pressure":38.0},{"time":"01:33:10","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":266.0,"rpm":25.0,"temp":122.0,"pressure":31.0},{"time":"01:33:16","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":255.0,"rpm":25.0,"temp":123.0,"pressure":33.0},{"time":"01:33:21","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":263.0,"rpm":25.0,"temp":125.0,"pressure":35.0},{"time":"01:33:26","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":259.0,"rpm":25.0,"temp":126.0,"pressure":31.0},{"time":"01:33:31","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":29.0,"current":236.0,"rpm":25.0,"temp":128.0,"pressure":30.0},{"time":"01:41:45","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":177.0,"rpm":30.0,"temp":94.0,"pressure":16.0},{"time":"01:41:50","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":319.0,"rpm":30.0,"temp":97.0,"pressure":8.0},{"time":"01:41:55","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":177.0,"rpm":30.0,"temp":95.0,"pressure":25.0},{"time":"01:42:01","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":202.0,"rpm":30.0,"temp":99.0,"pressure":25.0},{"time":"01:42:06","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":238.0,"rpm":30.0,"temp":97.0,"pressure":25.0},{"time":"01:42:15","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":324.0,"rpm":30.0,"temp":99.0,"pressure":34.0},{"time":"01:42:21","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":304.0,"rpm":30.0,"temp":100.0,"pressure":44.0},{"time":"01:42:26","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":296.0,"rpm":30.0,"temp":100.0,"pressure":40.0},{"time":"01:42:35","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":303.0,"rpm":30.0,"temp":102.0,"pressure":48.0},{"time":"01:42:40","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":288.0,"rpm":30.0,"temp":104.0,"pressure":30.0},{"time":"01:42:45","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":204.0,"rpm":30.0,"temp":105.0,"pressure":27.0},{"time":"01:42:50","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":156.0,"rpm":25.0,"temp":104.0,"pressure":25.0},{"time":"01:42:56","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":169.0,"rpm":25.0,"temp":106.0,"pressure":24.0},{"time":"01:43:01","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":256.0,"rpm":25.0,"temp":107.0,"pressure":38.0},{"time":"01:43:06","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":286.0,"rpm":25.0,"temp":108.0,"pressure":43.0},{"time":"01:43:15","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":285.0,"rpm":25.0,"temp":111.0,"pressure":46.0},{"time":"01:43:20","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":280.0,"rpm":25.0,"temp":114.0,"pressure":25.0},{"time":"01:43:25","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":274.0,"rpm":25.0,"temp":114.0,"pressure":41.0},{"time":"01:43:31","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":279.0,"rpm":25.0,"temp":117.0,"pressure":38.0},{"time":"01:43:36","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":273.0,"rpm":25.0,"temp":118.0,"pressure":33.0},{"time":"01:43:41","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":276.0,"rpm":25.0,"temp":120.0,"pressure":35.0},{"time":"01:43:50","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":263.0,"rpm":25.0,"temp":123.0,"pressure":29.0},{"time":"01:43:55","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":262.0,"rpm":25.0,"temp":125.0,"pressure":37.0},{"time":"01:44:00","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":260.0,"rpm":25.0,"temp":126.0,"pressure":36.0},{"time":"01:44:05","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":257.0,"rpm":25.0,"temp":128.0,"pressure":32.0},{"time":"01:44:11","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":30.0,"current":197.0,"rpm":25.0,"temp":129.0,"pressure":23.0},{"time":"01:51:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":145.0,"rpm":30.0,"temp":93.0,"pressure":9.0},{"time":"01:52:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":243.0,"rpm":30.0,"temp":97.0,"pressure":29.0},{"time":"01:52:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":168.0,"rpm":30.0,"temp":94.0,"pressure":24.0},{"time":"01:52:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":176.0,"rpm":30.0,"temp":94.0,"pressure":25.0},{"time":"01:52:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":186.0,"rpm":30.0,"temp":94.0,"pressure":13.0},{"time":"01:52:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":192.0,"rpm":30.0,"temp":95.0,"pressure":25.0},{"time":"01:52:29","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":297.0,"rpm":30.0,"temp":96.0,"pressure":29.0},{"time":"01:52:34","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":285.0,"rpm":30.0,"temp":96.0,"pressure":28.0},{"time":"01:52:39","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":303.0,"rpm":30.0,"temp":98.0,"pressure":28.0},{"time":"01:52:48","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":296.0,"rpm":30.0,"temp":101.0,"pressure":32.0},{"time":"01:52:53","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":215.0,"rpm":30.0,"temp":102.0,"pressure":69.0},{"time":"01:52:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":170.0,"rpm":26.0,"temp":103.0,"pressure":10.0},{"time":"01:53:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":154.0,"rpm":25.0,"temp":103.0,"pressure":25.0},{"time":"01:53:09","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":210.0,"rpm":25.0,"temp":104.0,"pressure":31.0},{"time":"01:53:14","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":246.0,"rpm":25.0,"temp":105.0,"pressure":30.0},{"time":"01:53:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":265.0,"rpm":25.0,"temp":109.0,"pressure":39.0},{"time":"01:53:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":277.0,"rpm":25.0,"temp":111.0,"pressure":29.0},{"time":"01:53:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":273.0,"rpm":25.0,"temp":112.0,"pressure":38.0},{"time":"01:53:39","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":269.0,"rpm":25.0,"temp":114.0,"pressure":30.0},{"time":"01:53:44","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":265.0,"rpm":25.0,"temp":116.0,"pressure":40.0},{"time":"01:53:49","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":273.0,"rpm":25.0,"temp":117.0,"pressure":38.0},{"time":"01:53:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":259.0,"rpm":25.0,"temp":120.0,"pressure":29.0},{"time":"01:54:03","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":264.0,"rpm":25.0,"temp":123.0,"pressure":35.0},{"time":"01:54:09","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":258.0,"rpm":25.0,"temp":123.0,"pressure":39.0},{"time":"01:54:14","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":266.0,"rpm":25.0,"temp":126.0,"pressure":35.0},{"time":"01:54:19","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":31.0,"current":242.0,"rpm":25.0,"temp":127.0,"pressure":31.0},{"time":"02:02:10","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":226.0,"rpm":30.0,"temp":99.0,"pressure":10.0},{"time":"02:02:15","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":245.0,"rpm":30.0,"temp":97.0,"pressure":25.0},{"time":"02:02:20","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":129.0,"rpm":30.0,"temp":95.0,"pressure":26.0},{"time":"02:02:25","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":225.0,"rpm":30.0,"temp":93.0,"pressure":25.0},{"time":"02:02:31","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":210.0,"rpm":30.0,"temp":96.0,"pressure":21.0},{"time":"02:02:36","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":286.0,"rpm":30.0,"temp":95.0,"pressure":28.0},{"time":"02:02:41","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":304.0,"rpm":30.0,"temp":98.0,"pressure":41.0},{"time":"02:02:50","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":298.0,"rpm":30.0,"temp":99.0,"pressure":39.0},{"time":"02:02:55","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":297.0,"rpm":30.0,"temp":101.0,"pressure":40.0},{"time":"02:03:01","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":293.0,"rpm":30.0,"temp":102.0,"pressure":31.0},{"time":"02:03:06","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":205.0,"rpm":30.0,"temp":103.0,"pressure":34.0},{"time":"02:03:11","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":32.0,"current":181.0,"rpm":25.0,"temp":103.0,"pressure":25.0},{"time":"10:55:58","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":250.0,"rpm":30.0,"temp":104.0,"pressure":58.0},{"time":"10:56:04","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":147.0,"rpm":25.0,"temp":105.0,"pressure":31.0},{"time":"10:56:09","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":200.0,"rpm":25.0,"temp":104.0,"pressure":15.0},{"time":"10:56:14","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":187.0,"rpm":25.0,"temp":106.0,"pressure":28.0},{"time":"10:56:23","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":287.0,"rpm":25.0,"temp":108.0,"pressure":42.0},{"time":"10:56:28","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":286.0,"rpm":25.0,"temp":110.0,"pressure":33.0},{"time":"10:56:33","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":275.0,"rpm":25.0,"temp":112.0,"pressure":33.0},{"time":"10:56:38","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":279.0,"rpm":25.0,"temp":114.0,"pressure":35.0},{"time":"10:56:43","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":274.0,"rpm":25.0,"temp":114.0,"pressure":36.0},{"time":"10:56:49","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":272.0,"rpm":25.0,"temp":117.0,"pressure":33.0},{"time":"10:56:54","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":261.0,"rpm":25.0,"temp":118.0,"pressure":34.0},{"time":"10:56:59","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":274.0,"rpm":25.0,"temp":120.0,"pressure":38.0},{"time":"10:57:08","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":267.0,"rpm":25.0,"temp":124.0,"pressure":35.0},{"time":"10:57:13","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":264.0,"rpm":25.0,"temp":125.0,"pressure":32.0},{"time":"10:57:18","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":257.0,"rpm":25.0,"temp":126.0,"pressure":43.0},{"time":"10:57:24","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":17.0,"current":238.0,"rpm":25.0,"temp":129.0,"pressure":30.0},{"time":"12:03:48","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":209.0,"rpm":30.0,"temp":95.0,"pressure":5.0},{"time":"12:03:53","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":200.0,"rpm":30.0,"temp":98.0,"pressure":12.0},{"time":"12:03:58","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":120.0,"rpm":17.0,"temp":91.0,"pressure":22.0},{"time":"12:04:03","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":206.0,"rpm":19.0,"temp":2.0,"pressure":25.0},{"time":"12:04:08","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":115.0,"rpm":27.0,"temp":85.0,"pressure":14.0},{"time":"12:04:13","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":151.0,"rpm":30.0,"temp":90.0,"pressure":12.0},{"time":"12:04:18","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":132.0,"rpm":30.0,"temp":88.0,"pressure":10.0},{"time":"12:04:24","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":176.0,"rpm":30.0,"temp":97.0,"pressure":25.0},{"time":"12:04:33","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":218.0,"rpm":30.0,"temp":98.0,"pressure":16.0},{"time":"12:04:38","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":247.0,"rpm":30.0,"temp":97.0,"pressure":24.0},{"time":"12:04:43","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":312.0,"rpm":30.0,"temp":98.0,"pressure":27.0},{"time":"12:04:48","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":319.0,"rpm":30.0,"temp":98.0,"pressure":36.0},{"time":"12:04:53","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":314.0,"rpm":30.0,"temp":101.0,"pressure":43.0},{"time":"12:04:58","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":311.0,"rpm":30.0,"temp":100.0,"pressure":45.0},{"time":"12:05:08","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":232.0,"rpm":30.0,"temp":103.0,"pressure":79.0},{"time":"12:05:13","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":188.0,"rpm":26.0,"temp":105.0,"pressure":13.0},{"time":"12:05:18","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":162.0,"rpm":25.0,"temp":104.0,"pressure":25.0},{"time":"12:05:23","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":203.0,"rpm":25.0,"temp":105.0,"pressure":24.0},{"time":"12:05:28","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":278.0,"rpm":25.0,"temp":106.0,"pressure":34.0},{"time":"12:05:34","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":269.0,"rpm":25.0,"temp":108.0,"pressure":24.0},{"time":"12:05:43","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":277.0,"rpm":25.0,"temp":111.0,"pressure":25.0},{"time":"12:05:48","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":264.0,"rpm":25.0,"temp":112.0,"pressure":32.0},{"time":"12:05:53","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":276.0,"rpm":25.0,"temp":113.0,"pressure":34.0},{"time":"12:05:58","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":263.0,"rpm":25.0,"temp":114.0,"pressure":29.0},{"time":"12:06:03","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":269.0,"rpm":25.0,"temp":116.0,"pressure":30.0},{"time":"12:06:08","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":265.0,"rpm":25.0,"temp":118.0,"pressure":34.0},{"time":"12:06:13","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":263.0,"rpm":25.0,"temp":119.0,"pressure":39.0},{"time":"12:06:19","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":262.0,"rpm":25.0,"temp":121.0,"pressure":24.0},{"time":"12:06:28","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":266.0,"rpm":25.0,"temp":124.0,"pressure":27.0},{"time":"12:06:33","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":258.0,"rpm":25.0,"temp":124.0,"pressure":36.0},{"time":"12:06:38","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":256.0,"rpm":25.0,"temp":127.0,"pressure":27.0},{"time":"12:06:43","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":18.0,"current":193.0,"rpm":25.0,"temp":127.0,"pressure":59.0},{"time":"12:13:58","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":159.0,"rpm":30.0,"temp":96.0,"pressure":9.0},{"time":"12:14:03","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":144.0,"rpm":30.0,"temp":98.0,"pressure":9.0},{"time":"12:14:08","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":169.0,"rpm":30.0,"temp":96.0,"pressure":25.0},{"time":"12:14:13","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":146.0,"rpm":30.0,"temp":96.0,"pressure":24.0},{"time":"12:14:18","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":156.0,"rpm":30.0,"temp":97.0,"pressure":24.0},{"time":"12:14:24","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":288.0,"rpm":30.0,"temp":96.0,"pressure":27.0},{"time":"12:14:33","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":287.0,"rpm":30.0,"temp":100.0,"pressure":36.0},{"time":"12:14:38","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":287.0,"rpm":30.0,"temp":101.0,"pressure":44.0},{"time":"12:14:43","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":292.0,"rpm":30.0,"temp":102.0,"pressure":40.0},{"time":"12:14:48","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":280.0,"rpm":30.0,"temp":103.0,"pressure":60.0},{"time":"12:14:53","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":194.0,"rpm":30.0,"temp":104.0,"pressure":32.0},{"time":"12:14:58","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":181.0,"rpm":25.0,"temp":102.0,"pressure":25.0},{"time":"12:15:03","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":179.0,"rpm":25.0,"temp":102.0,"pressure":23.0},{"time":"12:15:08","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":225.0,"rpm":25.0,"temp":105.0,"pressure":23.0},{"time":"12:15:14","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":285.0,"rpm":25.0,"temp":106.0,"pressure":32.0},{"time":"12:15:23","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":276.0,"rpm":25.0,"temp":109.0,"pressure":40.0},{"time":"12:15:28","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":282.0,"rpm":25.0,"temp":112.0,"pressure":34.0},{"time":"12:15:33","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":282.0,"rpm":25.0,"temp":112.0,"pressure":31.0},{"time":"12:15:38","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":284.0,"rpm":25.0,"temp":115.0,"pressure":32.0},{"time":"12:15:43","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":276.0,"rpm":25.0,"temp":115.0,"pressure":36.0},{"time":"12:15:48","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":275.0,"rpm":25.0,"temp":118.0,"pressure":34.0},{"time":"12:15:54","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":264.0,"rpm":25.0,"temp":119.0,"pressure":29.0},{"time":"12:16:03","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":269.0,"rpm":25.0,"temp":123.0,"pressure":35.0},{"time":"12:16:08","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":265.0,"rpm":25.0,"temp":124.0,"pressure":37.0},{"time":"12:16:13","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":263.0,"rpm":25.0,"temp":126.0,"pressure":28.0},{"time":"12:16:18","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":255.0,"rpm":25.0,"temp":127.0,"pressure":25.0},{"time":"12:16:23","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":19.0,"current":175.0,"rpm":25.0,"temp":128.0,"pressure":21.0},{"time":"12:23:45","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":239.0,"rpm":30.0,"temp":99.0,"pressure":10.0},{"time":"12:23:50","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":179.0,"rpm":30.0,"temp":96.0,"pressure":25.0},{"time":"12:23:55","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":192.0,"rpm":30.0,"temp":96.0,"pressure":25.0},{"time":"12:24:00","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":228.0,"rpm":30.0,"temp":103.0,"pressure":18.0},{"time":"12:24:05","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":275.0,"rpm":30.0,"temp":98.0,"pressure":30.0},{"time":"12:24:15","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":269.0,"rpm":30.0,"temp":97.0,"pressure":27.0},{"time":"12:24:20","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":291.0,"rpm":30.0,"temp":101.0,"pressure":25.0},{"time":"12:24:25","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":287.0,"rpm":30.0,"temp":100.0,"pressure":34.0},{"time":"12:24:30","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":278.0,"rpm":30.0,"temp":102.0,"pressure":25.0},{"time":"12:24:35","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":211.0,"rpm":30.0,"temp":102.0,"pressure":49.0},{"time":"12:24:40","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":166.0,"rpm":25.0,"temp":102.0,"pressure":29.0},{"time":"12:24:45","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":159.0,"rpm":25.0,"temp":102.0,"pressure":15.0},{"time":"12:24:50","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":233.0,"rpm":25.0,"temp":103.0,"pressure":25.0},{"time":"12:24:55","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":269.0,"rpm":25.0,"temp":105.0,"pressure":35.0},{"time":"12:25:01","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":276.0,"rpm":25.0,"temp":107.0,"pressure":28.0},{"time":"12:25:10","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":277.0,"rpm":25.0,"temp":110.0,"pressure":31.0},{"time":"12:25:15","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":269.0,"rpm":25.0,"temp":111.0,"pressure":32.0},{"time":"12:25:20","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":281.0,"rpm":25.0,"temp":113.0,"pressure":33.0},{"time":"12:25:25","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":262.0,"rpm":25.0,"temp":114.0,"pressure":36.0},{"time":"12:25:35","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":270.0,"rpm":25.0,"temp":118.0,"pressure":32.0},{"time":"12:25:40","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":262.0,"rpm":25.0,"temp":119.0,"pressure":39.0},{"time":"12:25:45","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":265.0,"rpm":25.0,"temp":122.0,"pressure":31.0},{"time":"12:25:50","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":264.0,"rpm":25.0,"temp":122.0,"pressure":29.0},{"time":"12:25:55","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":267.0,"rpm":25.0,"temp":124.0,"pressure":31.0},{"time":"12:26:01","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":260.0,"rpm":25.0,"temp":124.0,"pressure":38.0},{"time":"12:26:10","date":"2026/06/06","formula":"TC16Q","shift":"A","status":1,"batch":20.0,"current":177.0,"rpm":25.0,"temp":127.0,"pressure":40.0},{"time":"12:34:01","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":240.0,"rpm":30.0,"temp":92.0,"pressure":9.0},{"time":"12:34:06","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":218.0,"rpm":30.0,"temp":97.0,"pressure":26.0},{"time":"12:34:11","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":250.0,"rpm":30.0,"temp":95.0,"pressure":25.0},{"time":"12:34:16","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":216.0,"rpm":30.0,"temp":94.0,"pressure":25.0},{"time":"12:34:21","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":148.0,"rpm":30.0,"temp":92.0,"pressure":20.0},{"time":"12:34:27","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":256.0,"rpm":30.0,"temp":98.0,"pressure":25.0},{"time":"12:34:36","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":299.0,"rpm":30.0,"temp":99.0,"pressure":39.0},{"time":"12:34:41","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":303.0,"rpm":30.0,"temp":99.0,"pressure":43.0},{"time":"12:34:46","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":301.0,"rpm":30.0,"temp":100.0,"pressure":33.0},{"time":"12:34:51","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":285.0,"rpm":30.0,"temp":101.0,"pressure":30.0},{"time":"12:34:56","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":188.0,"rpm":30.0,"temp":103.0,"pressure":65.0},{"time":"12:35:06","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":163.0,"rpm":25.0,"temp":103.0,"pressure":25.0},{"time":"12:35:11","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":236.0,"rpm":25.0,"temp":103.0,"pressure":26.0},{"time":"12:35:16","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":251.0,"rpm":25.0,"temp":105.0,"pressure":26.0},{"time":"12:35:21","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":278.0,"rpm":25.0,"temp":108.0,"pressure":28.0},{"time":"12:35:26","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":279.0,"rpm":25.0,"temp":109.0,"pressure":43.0},{"time":"12:35:31","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":280.0,"rpm":25.0,"temp":110.0,"pressure":32.0},{"time":"12:35:41","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":263.0,"rpm":25.0,"temp":113.0,"pressure":29.0},{"time":"12:35:46","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":271.0,"rpm":25.0,"temp":116.0,"pressure":35.0},{"time":"12:35:51","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":262.0,"rpm":25.0,"temp":116.0,"pressure":37.0},{"time":"12:35:56","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":268.0,"rpm":25.0,"temp":119.0,"pressure":31.0},{"time":"12:36:01","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":264.0,"rpm":25.0,"temp":120.0,"pressure":32.0},{"time":"12:36:06","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":267.0,"rpm":25.0,"temp":123.0,"pressure":34.0},{"time":"12:36:11","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":259.0,"rpm":25.0,"temp":124.0,"pressure":37.0},{"time":"12:36:21","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":263.0,"rpm":25.0,"temp":127.0,"pressure":68.0},{"time":"12:36:26","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":21.0,"current":173.0,"rpm":25.0,"temp":127.0,"pressure":22.0},{"time":"12:44:26","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":233.0,"rpm":30.0,"temp":99.0,"pressure":10.0},{"time":"12:44:31","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":208.0,"rpm":30.0,"temp":97.0,"pressure":25.0},{"time":"12:44:36","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":175.0,"rpm":30.0,"temp":96.0,"pressure":25.0},{"time":"12:44:41","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":194.0,"rpm":30.0,"temp":94.0,"pressure":25.0},{"time":"12:44:46","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":197.0,"rpm":30.0,"temp":96.0,"pressure":22.0},{"time":"12:44:51","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":270.0,"rpm":30.0,"temp":96.0,"pressure":32.0},{"time":"12:45:01","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":285.0,"rpm":30.0,"temp":98.0,"pressure":34.0},{"time":"12:45:06","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":276.0,"rpm":30.0,"temp":100.0,"pressure":41.0},{"time":"12:45:11","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":284.0,"rpm":30.0,"temp":101.0,"pressure":42.0},{"time":"12:45:16","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":275.0,"rpm":30.0,"temp":102.0,"pressure":24.0},{"time":"12:45:21","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":197.0,"rpm":30.0,"temp":101.0,"pressure":40.0},{"time":"12:45:26","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":178.0,"rpm":25.0,"temp":104.0,"pressure":24.0},{"time":"12:45:31","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":174.0,"rpm":25.0,"temp":105.0,"pressure":12.0},{"time":"12:45:37","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":196.0,"rpm":25.0,"temp":105.0,"pressure":25.0},{"time":"12:45:46","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":271.0,"rpm":25.0,"temp":109.0,"pressure":42.0},{"time":"12:45:51","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":286.0,"rpm":25.0,"temp":110.0,"pressure":31.0},{"time":"12:45:56","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":277.0,"rpm":25.0,"temp":112.0,"pressure":31.0},{"time":"12:46:01","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":279.0,"rpm":25.0,"temp":113.0,"pressure":43.0},{"time":"12:46:06","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":280.0,"rpm":25.0,"temp":115.0,"pressure":26.0},{"time":"12:46:11","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":267.0,"rpm":25.0,"temp":115.0,"pressure":33.0},{"time":"12:46:16","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":273.0,"rpm":25.0,"temp":117.0,"pressure":39.0},{"time":"12:46:26","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":271.0,"rpm":25.0,"temp":121.0,"pressure":33.0},{"time":"12:46:31","date":"2026/06/06","formula":"39Q1","shift":"A","status":1,"batch":22.0,"current":268.0,"rpm":25.0,"temp":122.0,"pressure":37.0}];

// ---- Domain mapping (single source of truth for CSV header -> field name) ----
const COLUMN_MAP = {
  "时间": "time", "日期": "date", "示方名称": "formula", "班次": "shift",
  "设备状态": "status", "当前批次": "batch", "主机电流": "current",
  "主机转速": "rpm", "胶料温度": "temp", "上顶栓压力": "pressure",
};

const METRICS = [
  { key: "current", label: "主机电流", sub: "Main Motor Current", unit: "A", color: "#c2410c" },
  { key: "rpm", label: "主机转速", sub: "Main Motor Speed", unit: "rpm", color: "#0369a1" },
  { key: "temp", label: "胶料温度", sub: "Compound Temperature", unit: "\u00b0C", color: "#b91c1c" },
  { key: "pressure", label: "上顶栓压力", sub: "Upper Ram Pressure", unit: "bar", color: "#15803d" },
];

// Known bad-sensor window (temp sensor stuck at ~441 this whole span)
const TEMP_FAULT_START = "2026/05/11";
const TEMP_FAULT_END = "2026/05/18";

function parseCsvRows(raw) {
  const result = Papa.parse(raw, { header: true, skipEmptyLines: true });
  return result.data.map((row) => {
    const out = {};
    for (const [zh, en] of Object.entries(COLUMN_MAP)) {
      if (row[zh] !== undefined) {
        const v = row[zh];
        out[en] = ["current", "rpm", "temp", "pressure", "status", "batch"].includes(en)
          ? parseFloat(v) : v;
      }
    }
    return out;
  }).filter((r) => r.time && r.date);
}

function parseDateTime(dateStr, timeStr) {
  // dateStr "YYYY/MM/DD", timeStr "HH:MM:SS"
  const [y, mo, d] = dateStr.split("/").map(Number);
  const [h, mi, s] = timeStr.split(":").map(Number);
  return new Date(y, mo - 1, d, h, mi, s);
}

function ymd(dt) {
  return `${dt.getFullYear()}/${String(dt.getMonth() + 1).padStart(2, "0")}/${String(dt.getDate()).padStart(2, "0")}`;
}

function productionDate(dt) {
  // 8am-to-8am production day: before 08:00 belongs to the previous calendar day
  if (dt.getHours() < 8) {
    const prev = new Date(dt);
    prev.setDate(dt.getDate() - 1);
    return ymd(prev);
  }
  return ymd(dt);
}

// Converts elapsed seconds (from a segment's start) back to an HH:MM:SS clock label,
// given the segment's start Date. Used so time-proportional axes still read as clock time.
function elapsedToClock(startDt, elapsedS) {
  const d = new Date(startDt.getTime() + elapsedS * 1000);
  const pad = (n) => String(n).padStart(2, "0");
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function formatDuration(sec) {
  if (sec < 60) return `${sec}s`;
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}m ${s}s`;
}

// "Nice" evenly-spaced ticks (1/2/5 * 10^n step) so the Y axis increments at a
// constant rate — e.g. 90,100,110,120,130 rather than whatever falls out of
// arbitrary min/max padding.
function niceTicks(min, max, targetCount = 5) {
  const range = max - min || 1;
  const roughStep = range / (targetCount - 1);
  const magnitude = Math.pow(10, Math.floor(Math.log10(roughStep)));
  const residual = roughStep / magnitude;
  const niceResidual = residual > 5 ? 10 : residual > 2 ? 5 : residual > 1 ? 2 : 1;
  const step = niceResidual * magnitude;

  const niceMin = Math.floor(min / step) * step;
  const niceMax = Math.ceil(max / step) * step;
  const ticks = [];
  for (let v = niceMin; v <= niceMax + step / 2; v += step) {
    ticks.push(Math.round(v * 100) / 100);
  }
  return { ticks, domain: [niceMin, niceMax] };
}

// ---- Segmentation: batch boundary = raw batch id changes OR gap > 60s ----
function computeSegments(rows) {
  const withDt = rows
    .map((r) => ({ ...r, dt: parseDateTime(r.date, r.time) }))
    .filter((r) => !isNaN(r.dt.getTime()))
    .sort((a, b) => a.dt - b.dt);

  const segments = [];
  let current = null;

  withDt.forEach((r, i) => {
    const prev = withDt[i - 1];
    const gapS = prev ? (r.dt - prev.dt) / 1000 : Infinity;
    const batchChanged = !prev || prev.batch !== r.batch;
    const isNewSegment = gapS > 60 || batchChanged;

    if (isNewSegment) {
      if (current) segments.push(current);
      current = {
        id: segments.length,
        productionDate: productionDate(r.dt),
        formula: r.formula,
        rawBatch: r.batch,
        readings: [],
      };
    }
    current.readings.push(r);
  });
  if (current) segments.push(current);

  // enrich each segment: timing, mode, flags
  segments.forEach((seg) => {
    const rs = seg.readings;
    seg.start = rs[0].dt;
    seg.end = rs[rs.length - 1].dt;
    seg.durationS = Math.round((seg.end - seg.start) / 1000);
    seg.n = rs.length;
    // numeric seconds-since-batch-start, so chart X axes advance at a constant
    // rate instead of spacing points evenly regardless of the actual gap between them
    rs.forEach((r) => { r.t = (r.dt - seg.start) / 1000; });

    const statuses = new Set(rs.map((r) => r.status));
    seg.mode = statuses.size > 1 ? "Mixed" : statuses.has(2) ? "Manual" : "Auto";

    const flags = [];
    if (seg.productionDate >= TEMP_FAULT_START && seg.productionDate <= TEMP_FAULT_END) {
      flags.push("Temp sensor fault window");
    }
    if (seg.n < 5) flags.push("Very short segment \u2014 possible noise");
    seg.flags = flags;
  });

  // assign batch_of_day per production day, ordered by start time (NOT the raw counter)
  const byDay = {};
  segments.forEach((seg) => {
    (byDay[seg.productionDate] ||= []).push(seg);
  });
  Object.values(byDay).forEach((list) => {
    list.sort((a, b) => a.start - b.start);
    list.forEach((seg, i) => { seg.batchOfDay = i + 1; });
  });

  return segments.sort((a, b) => a.start - b.start);
}

// ---- Multi-batch view: concatenate several batches on one virtual timeline ----
// Within a batch, spacing is real elapsed time (so the shape of the mix cycle is
// accurate). Between batches, the idle gap is compressed to a constant width
// (GAP_VT "virtual seconds") regardless of how long the real gap was, so five or
// ten batches' worth of idle time doesn't dwarf the actual data. The real gap
// duration is preserved and shown via BatchLegend below the chart, not on the axis.
const GAP_VT = 20;

function buildMultiBatchSeries(slice) {
  let offset = 0;
  const data = [];
  const boundaryVts = [];
  slice.forEach((seg, i) => {
    if (i > 0) offset += GAP_VT;
    const segStart = offset;
    if (i > 0) boundaryVts.push(segStart);
    seg.readings.forEach((r) => {
      data.push({ ...r, vt: segStart + (r.dt - seg.start) / 1000 });
    });
    offset = segStart + seg.durationS;
  });
  return { data, totalVt: offset, boundaryVts };
}

// Chips showing each batch's number/start time, with the real (uncompressed) idle
// duration between consecutive batches — this is the "indicate the time below" bit.
function BatchLegend({ slice }) {
  return (
    <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 6, marginTop: 10, marginBottom: 20, fontSize: 11 }}>
      {slice.map((seg, i) => (
        <span key={seg.id} style={{ display: "flex", alignItems: "center", gap: 6 }}>
          {i > 0 && (
            <span style={{ color: "#94a3b8" }}>
              \u23f8 {formatDuration(Math.round((seg.start - slice[i - 1].end) / 1000))}
            </span>
          )}
          <span style={{ background: "#f1f5f9", padding: "2px 8px", borderRadius: 12, fontWeight: 600, color: "#334155" }}>
            #{seg.batchOfDay} <span style={{ fontWeight: 400, color: "#94a3b8" }}>{seg.readings[0].time}</span>
          </span>
        </span>
      ))}
    </div>
  );
}

// ---- Individual mode: 4 stacked small-multiple charts ----
function IndividualCharts({ readings, xKey = "t", xDomain, tickFormatter, boundaries = [] }) {
  return (
    <>
      {METRICS.map((m) => {
        const values = readings.map((d) => d[m.key]).filter((v) => !Number.isNaN(v));
        const min = Math.min(...values);
        const max = Math.max(...values);
        const { ticks, domain } = niceTicks(min, max, 5);
        return (
          <div key={m.key} style={{ marginBottom: 20 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 4 }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#1e293b" }}>{m.label} <span style={{ fontWeight: 400, color: "#94a3b8" }}>{m.sub}</span></span>
              <span style={{ fontSize: 11, color: "#64748b" }}>min {min.toFixed(1)} \u00b7 max {max.toFixed(1)} {m.unit}</span>
            </div>
            <ResponsiveContainer width="100%" height={120}>
              <LineChart data={readings} margin={{ top: 4, right: 12, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="2 4" stroke="#e2e8f0" />
                <XAxis
                  dataKey={xKey}
                  type="number"
                  domain={xDomain}
                  tickFormatter={tickFormatter || undefined}
                  tick={tickFormatter ? { fontSize: 10, fill: "#64748b" } : false}
                  minTickGap={40}
                />
                <YAxis domain={domain} ticks={ticks} tick={{ fontSize: 10, fill: "#64748b" }} width={40} />
                <Tooltip
                  formatter={(v) => [`${v} ${m.unit}`, m.label]}
                  labelFormatter={tickFormatter ? (t) => `Time: ${tickFormatter(t)}` : undefined}
                  contentStyle={{ fontSize: 12, borderRadius: 6 }}
                />
                {boundaries.map((bx, idx) => (
                  <ReferenceLine key={idx} x={bx} stroke="#94a3b8" strokeDasharray="3 3" />
                ))}
                <Line type="monotone" dataKey={m.key} stroke={m.color} strokeWidth={2} dot={{ r: 2 }} activeDot={{ r: 4 }} isAnimationActive={false} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        );
      })}
    </>
  );
}

// ---- Merged mode: one time axis, each metric independently auto-scaled (hidden axes) ----
// Axes are hidden because 4 overlapping numeric scales are unreadable as tick labels;
// the legend below carries each metric's actual min/max, and the tooltip carries exact values.
function MergedChart({ readings, xKey = "t", xDomain, tickFormatter, boundaries = [] }) {
  const ranges = METRICS.map((m) => {
    const values = readings.map((d) => d[m.key]).filter((v) => !Number.isNaN(v));
    const min = Math.min(...values);
    const max = Math.max(...values);
    const pad = (max - min) * 0.1 || 1;
    return { ...m, min, max, domain: [min - pad, max + pad] };
  });

  return (
    <div>
      <ResponsiveContainer width="100%" height={340}>
        <LineChart data={readings} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="2 4" stroke="#e2e8f0" />
          <XAxis
            dataKey={xKey}
            type="number"
            domain={xDomain}
            tickFormatter={tickFormatter || undefined}
            tick={tickFormatter ? { fontSize: 10, fill: "#64748b" } : false}
            minTickGap={40}
          />
          {ranges.map((m) => (
            <YAxis key={m.key} yAxisId={m.key} domain={m.domain} hide />
          ))}
          <Tooltip
            labelFormatter={tickFormatter ? (t) => `Time: ${tickFormatter(t)}` : undefined}
            formatter={(value, name) => {
              const m = METRICS.find((x) => x.label === name);
              return [`${value} ${m ? m.unit : ""}`, name];
            }}
            contentStyle={{ fontSize: 12, borderRadius: 6 }}
          />
          {boundaries.map((bx, idx) => (
            <ReferenceLine key={idx} x={bx} stroke="#94a3b8" strokeDasharray="3 3" />
          ))}
          {ranges.map((m) => (
            <Line key={m.key} yAxisId={m.key} type="monotone" dataKey={m.key} name={m.label}
              stroke={m.color} strokeWidth={2} dot={false} activeDot={{ r: 4 }} isAnimationActive={false} />
          ))}
        </LineChart>
      </ResponsiveContainer>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: 6, marginTop: 8 }}>
        {ranges.map((m) => (
          <div key={m.key} style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 11, color: "#475569" }}>
            <span style={{ width: 10, height: 10, borderRadius: 2, background: m.color, flexShrink: 0 }} />
            <span style={{ fontWeight: 600 }}>{m.label}</span>
            <span style={{ color: "#94a3b8" }}>{m.sub}: {m.min.toFixed(1)}\u2013{m.max.toFixed(1)} {m.unit} (own scale)</span>
          </div>
        ))}
      </div>
    </div>
  );
}

const MODE_COLORS = { Auto: "#0369a1", Manual: "#b45309", Mixed: "#7c3aed" };

export default function BanburyDashboard() {
  const [rawRows, setRawRows] = useState(SAMPLE_ROWS);
  const [fileName, setFileName] = useState("Demo sample: 2026/06/06 (450 readings)");
  const [error, setError] = useState(null);
  const [selectedId, setSelectedId] = useState(null);
  const [chartMode, setChartMode] = useState("individual");
  const [batchCount, setBatchCount] = useState(1);

  const [filterDate, setFilterDate] = useState(null); // null = not yet initialized to latest date
  const [filterFormula, setFilterFormula] = useState("all");
  const [filterMode, setFilterMode] = useState("all");

  const segments = useMemo(() => computeSegments(rawRows), [rawRows]);

  const dates = useMemo(() => [...new Set(segments.map((s) => s.productionDate))].sort(), [segments]);
  const formulas = useMemo(() => [...new Set(segments.map((s) => s.formula))].sort(), [segments]);

  // Default view: most recent production date, not "all" — with 3,000+ batches
  // in the real dataset, rendering everything unfiltered isn't useful or fast.
  const effectiveDate = filterDate === null ? (dates[dates.length - 1] ?? "all") : filterDate;

  const ALL_DATES_CAP = 200;
  const preCapFiltered = useMemo(() => {
    return segments.filter((s) =>
      (effectiveDate === "all" || s.productionDate === effectiveDate) &&
      (filterFormula === "all" || s.formula === filterFormula) &&
      (filterMode === "all" || s.mode === filterMode)
    );
  }, [segments, effectiveDate, filterFormula, filterMode]);

  const isCapped = effectiveDate === "all" && preCapFiltered.length > ALL_DATES_CAP;
  const filtered = isCapped ? preCapFiltered.slice(0, ALL_DATES_CAP) : preCapFiltered;

  const selected = segments.find((s) => s.id === selectedId);

  // "N batches starting from here" walks forward through the full chronological
  // segment list (not the filtered list) — a formula/mode filter narrowing the
  // table shouldn't skip real consecutive batches in the comparison view.
  const selectedIndex = selectedId == null ? -1 : segments.findIndex((s) => s.id === selectedId);
  const sliceForChart = selectedIndex === -1 ? [] : segments.slice(selectedIndex, selectedIndex + batchCount);
  const multiSeries = useMemo(
    () => (batchCount > 1 ? buildMultiBatchSeries(sliceForChart) : null),
    [sliceForChart, batchCount]
  );

  const handleFile = useCallback((e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setError(null);
    const reader = new FileReader();
    reader.onload = (ev) => {
      try {
        const parsed = parseCsvRows(ev.target.result);
        if (parsed.length === 0) {
          setError("No rows parsed. Check the CSV has the expected Chinese column headers.");
          return;
        }
        setRawRows(parsed);
        setFileName(file.name);
        setSelectedId(null);
        setFilterDate("all");
      } catch (err) {
        setError("Failed to parse file: " + err.message);
      }
    };
    reader.readAsText(file, "UTF-8");
  }, []);

  const wrap = { fontFamily: "system-ui, -apple-system, sans-serif", maxWidth: 780, margin: "0 auto", padding: 20, color: "#0f172a" };

  // ---------------- DETAIL VIEW ----------------
  if (selected) {
    return (
      <div style={wrap}>
        <button onClick={() => setSelectedId(null)} style={{
          display: "flex", alignItems: "center", gap: 4, background: "none", border: "none",
          color: "#0369a1", fontSize: 13, cursor: "pointer", padding: 0, marginBottom: 14,
        }}>
          <ChevronLeft size={16} /> Back to batch list
        </button>

        {batchCount === 1 ? (
          <div style={{
            display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8,
            background: "#f8fafc", border: "1px solid #e2e8f0", borderRadius: 8,
            padding: 12, marginBottom: 16, fontSize: 12,
          }}>
            <div><div style={{ color: "#94a3b8" }}>Batch</div><div style={{ fontWeight: 600 }}>#{selected.batchOfDay}</div></div>
            <div><div style={{ color: "#94a3b8" }}>Date</div><div style={{ fontWeight: 600 }}>{selected.productionDate}</div></div>
            <div><div style={{ color: "#94a3b8" }}>Rubber Type</div><div style={{ fontWeight: 600 }}>{selected.formula}</div></div>
            <div><div style={{ color: "#94a3b8" }}>Duration</div><div style={{ fontWeight: 600 }}>{formatDuration(selected.durationS)}</div></div>
            <div><div style={{ color: "#94a3b8" }}>Mode</div><div style={{ fontWeight: 600, color: MODE_COLORS[selected.mode] }}>{selected.mode}</div></div>
          </div>
        ) : (
          <div style={{
            display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 8,
            background: "#f8fafc", border: "1px solid #e2e8f0", borderRadius: 8,
            padding: 12, marginBottom: 16, fontSize: 12,
          }}>
            <div><div style={{ color: "#94a3b8" }}>Batches</div><div style={{ fontWeight: 600 }}>
              #{sliceForChart[0].batchOfDay}\u2013#{sliceForChart[sliceForChart.length - 1].batchOfDay}
              {sliceForChart.length < batchCount ? ` (${sliceForChart.length} of ${batchCount} \u2014 end of data)` : ""}
            </div></div>
            <div><div style={{ color: "#94a3b8" }}>Date</div><div style={{ fontWeight: 600 }}>{sliceForChart[0].productionDate}</div></div>
            <div><div style={{ color: "#94a3b8" }}>Rubber Type(s)</div><div style={{ fontWeight: 600 }}>{[...new Set(sliceForChart.map((s) => s.formula))].join(", ")}</div></div>
            <div><div style={{ color: "#94a3b8" }}>Mode(s)</div><div style={{ fontWeight: 600 }}>{[...new Set(sliceForChart.map((s) => s.mode))].join(", ")}</div></div>
          </div>
        )}

        {batchCount === 1 && selected.flags.length > 0 && (
          <div style={{
            display: "flex", gap: 8, alignItems: "flex-start", color: "#92400e",
            background: "#fffbeb", border: "1px solid #fde68a", borderRadius: 6,
            padding: 10, fontSize: 12, marginBottom: 16,
          }}>
            <AlertTriangle size={16} style={{ flexShrink: 0, marginTop: 1 }} />
            <span>{selected.flags.join(" \u00b7 ")}</span>
          </div>
        )}

        <div style={{ display: "flex", gap: 8, marginBottom: 10 }}>
          {[1, 5, 10].map((n) => (
            <button key={n} onClick={() => setBatchCount(n)} style={{
              padding: "6px 12px", borderRadius: 6, fontSize: 12,
              border: batchCount === n ? "1px solid #0369a1" : "1px solid #e2e8f0",
              background: batchCount === n ? "#eff6ff" : "#fff",
              color: batchCount === n ? "#0369a1" : "#64748b", cursor: "pointer",
            }}>
              {n === 1 ? "Single batch" : `${n} batches`}
            </button>
          ))}
        </div>

        <div style={{ display: "flex", gap: 8, marginBottom: 16 }}>
          <button onClick={() => setChartMode("individual")} style={{
            display: "flex", alignItems: "center", gap: 6, padding: "6px 12px", borderRadius: 6, fontSize: 12,
            border: chartMode === "individual" ? "1px solid #0369a1" : "1px solid #e2e8f0",
            background: chartMode === "individual" ? "#eff6ff" : "#fff",
            color: chartMode === "individual" ? "#0369a1" : "#64748b", cursor: "pointer",
          }}>
            <LayoutGrid size={14} /> Individual
          </button>
          <button onClick={() => setChartMode("merged")} style={{
            display: "flex", alignItems: "center", gap: 6, padding: "6px 12px", borderRadius: 6, fontSize: 12,
            border: chartMode === "merged" ? "1px solid #0369a1" : "1px solid #e2e8f0",
            background: chartMode === "merged" ? "#eff6ff" : "#fff",
            color: chartMode === "merged" ? "#0369a1" : "#64748b", cursor: "pointer",
          }}>
            <GitMerge size={14} /> Merged (\u81ea\u9002\u5e94)
          </button>
        </div>

        {batchCount === 1 ? (
          chartMode === "individual"
            ? <IndividualCharts readings={selected.readings} xKey="t" xDomain={[0, selected.readings[selected.readings.length - 1].t]} tickFormatter={(t) => elapsedToClock(selected.start, t)} />
            : <MergedChart readings={selected.readings} xKey="t" xDomain={[0, selected.readings[selected.readings.length - 1].t]} tickFormatter={(t) => elapsedToClock(selected.start, t)} />
        ) : (
          <>
            {chartMode === "individual"
              ? <IndividualCharts readings={multiSeries.data} xKey="vt" xDomain={[0, multiSeries.totalVt]} boundaries={multiSeries.boundaryVts} />
              : <MergedChart readings={multiSeries.data} xKey="vt" xDomain={[0, multiSeries.totalVt]} boundaries={multiSeries.boundaryVts} />}
            <BatchLegend slice={sliceForChart} />
          </>
        )}
      </div>
    );
  }

  // ---------------- LIST VIEW ----------------
  return (
    <div style={wrap}>
      <div style={{ marginBottom: 16 }}>
        <h2 style={{ fontSize: 18, fontWeight: 700, margin: 0 }}>Banbury Batch Dashboard \u2014 Q1 Side</h2>
        <p style={{ fontSize: 12, color: "#64748b", margin: "4px 0 0" }}>{fileName} \u00b7 {segments.length} batches detected</p>
      </div>

      <label style={{
        display: "flex", alignItems: "center", gap: 8, cursor: "pointer",
        border: "1px dashed #cbd5e1", borderRadius: 8, padding: "10px 14px",
        fontSize: 13, color: "#475569", marginBottom: 16, width: "fit-content",
      }}>
        <Upload size={16} />
        Load a CSV export from USB stick
        <input type="file" accept=".csv" onChange={handleFile} style={{ display: "none" }} />
      </label>

      {error && (
        <div style={{
          display: "flex", gap: 8, alignItems: "center", color: "#b91c1c",
          background: "#fef2f2", border: "1px solid #fecaca", borderRadius: 6,
          padding: 10, fontSize: 12, marginBottom: 16,
        }}>
          <FileWarning size={16} /> {error}
        </div>
      )}

      <div style={{ display: "flex", gap: 8, marginBottom: 14, flexWrap: "wrap" }}>
        <select value={effectiveDate} onChange={(e) => setFilterDate(e.target.value)} style={selectStyle}>
          <option value="all">All dates ({segments.length} batches)</option>
          {dates.map((d) => <option key={d} value={d}>{d}</option>)}
        </select>
        <select value={filterFormula} onChange={(e) => setFilterFormula(e.target.value)} style={selectStyle}>
          <option value="all">All rubber types</option>
          {formulas.map((f) => <option key={f} value={f}>{f}</option>)}
        </select>
        <select value={filterMode} onChange={(e) => setFilterMode(e.target.value)} style={selectStyle}>
          <option value="all">Auto + Manual</option>
          <option value="Auto">Auto only</option>
          <option value="Manual">Manual only</option>
          <option value="Mixed">Mixed only</option>
        </select>
      </div>

      {isCapped && (
        <div style={{ fontSize: 12, color: "#92400e", background: "#fffbeb", border: "1px solid #fde68a", borderRadius: 6, padding: "6px 10px", marginBottom: 10 }}>
          Showing first {ALL_DATES_CAP} of {preCapFiltered.length} matching batches. Pick a specific date to see the rest.
        </div>
      )}

      <div style={{ border: "1px solid #e2e8f0", borderRadius: 8, overflow: "hidden" }}>
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
          <thead>
            <tr style={{ background: "#f8fafc", textAlign: "left" }}>
              <th style={thStyle}>Batch</th>
              <th style={thStyle}>Time</th>
              <th style={thStyle}>Rubber Type</th>
              <th style={thStyle}>Duration</th>
              <th style={thStyle}>Mode</th>
              <th style={thStyle}></th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 && (
              <tr><td colSpan={6} style={{ padding: 16, textAlign: "center", color: "#94a3b8" }}>No batches match these filters.</td></tr>
            )}
            {filtered.map((s) => (
              <tr key={s.id} onClick={() => { setSelectedId(s.id); setBatchCount(1); }}
                style={{ borderTop: "1px solid #f1f5f9", cursor: "pointer" }}
                onMouseEnter={(e) => e.currentTarget.style.background = "#f8fafc"}
                onMouseLeave={(e) => e.currentTarget.style.background = "transparent"}>
                <td style={tdStyle}>#{s.batchOfDay}<span style={{ color: "#cbd5e1" }}> ({s.productionDate})</span></td>
                <td style={tdStyle}>{s.readings[0].time}</td>
                <td style={tdStyle}>{s.formula}</td>
                <td style={tdStyle}>{formatDuration(s.durationS)}</td>
                <td style={tdStyle}><span style={{ color: MODE_COLORS[s.mode], fontWeight: 600 }}>{s.mode}</span></td>
                <td style={tdStyle}>{s.flags.length > 0 && <AlertTriangle size={14} color="#d97706" />}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

const selectStyle = { fontSize: 12, padding: "6px 10px", borderRadius: 6, border: "1px solid #e2e8f0", color: "#334155", background: "#fff" };
const thStyle = { padding: "8px 10px", fontSize: 11, textTransform: "uppercase", letterSpacing: 0.3, color: "#64748b", fontWeight: 600 };
const tdStyle = { padding: "8px 10px" };
