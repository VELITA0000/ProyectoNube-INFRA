/**
 * EMF para métricas custom del worker (misma convención que la API).
 * @see https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html
 */
function emitEmfCount(metrics, dimensions) {
  const dimensionNames = Object.keys(dimensions).sort();
  const doc = {
    _aws: {
      Timestamp: Date.now(),
      CloudWatchMetrics: [
        {
          Namespace: "Lumiere/App",
          Dimensions: [dimensionNames],
          Metrics: Object.keys(metrics).map((name) => ({ Name: name, Unit: "Count" })),
        },
      ],
    },
    ...dimensions,
    ...metrics,
  };
  console.log(JSON.stringify(doc));
}

module.exports = { emitEmfCount };
