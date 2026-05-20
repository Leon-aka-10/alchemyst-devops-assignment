import { Logger, registerWorker } from 'iii-sdk';

// III_URL injected by systemd environment — points to engine VM private IP
const iii = registerWorker(process.env.III_URL ?? 'ws://localhost:49134');
const logger = new Logger();

// RPC function — called by other workers internally
iii.registerFunction(
  'inference::get_response',
  async (payload: { messages: Record<string, any> } & Record<string, any>) => {
    logger.info('inference::get_response called', { messageCount: payload.messages?.length });

    const result = await iii.trigger({
      function_id: 'inference::run_inference',
      payload,
    });

    return result;
  }
);

// HTTP trigger — bound to POST /v1/chat/completions
// Receives requests forwarded by NGINX from gateway VM
iii.registerFunction(
  'http::run_inference_over_http',
  async (payload: {
    body: { messages: Record<string, any>[] } & Record<string, any>
  }) => {
    logger.info('http::run_inference_over_http called');

    const result = await iii.trigger({
      function_id: 'inference::get_response',
      payload: payload.body,
    });

    return {
      status_code: 200,
      body: { result },
      headers: { 'Content-Type': 'application/json' },
    };
  }
);

iii.registerTrigger({
  type: 'http',
  function_id: 'http::run_inference_over_http',
  config: {
    api_path: '/v1/chat/completions',
    http_method: 'POST'
  },
});

logger.info(`Caller worker started — connecting to ${process.env.III_URL ?? 'ws://localhost:49134'}`);