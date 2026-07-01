#include <cstring>
#include <string>
#include <vector>

#include "llama.h"

extern "C" {

struct TgChatModel {
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
    int n_ctx = 0;
    int n_past = 0;
    int n_vocab = 0;
};

static bool tgchat_eval(TgChatModel* m, const std::vector<llama_token>& tokens) {
    if (tokens.empty()) return true;
    llama_batch batch = llama_batch_init((int)tokens.size(), 0, 1);
    for (size_t i = 0; i < tokens.size(); ++i) {
        batch.token[i] = tokens[i];
        batch.pos[i] = m->n_past + (int)i;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        batch.logits[i] = 0;
    }
    batch.logits[tokens.size() - 1] = 1;
    batch.n_tokens = (int32_t)tokens.size();
    if (llama_decode(m->ctx, batch) != 0) {
        llama_batch_free(batch);
        return false;
    }
    m->n_past += (int)tokens.size();
    llama_batch_free(batch);
    return true;
}

TgChatModel* tgchat_load_model(const char* path, int n_ctx, int n_threads, char* err, int err_size) {
    static bool backend_initialized = false;
    if (!backend_initialized) {
        llama_backend_init();
        backend_initialized = true;
    }

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;

    llama_model* model = llama_load_model_from_file(path, mparams);
    if (!model) {
        if (err && err_size > 0) snprintf(err, err_size, "failed to load model: %s", path);
        return nullptr;
    }

    llama_context_params cparams = llama_context_default_params();
    cparams.seed = 42;
    cparams.n_ctx = n_ctx > 0 ? n_ctx : 512;
    cparams.n_threads = n_threads > 0 ? n_threads : 4;
    cparams.n_threads_batch = cparams.n_threads;

    llama_context* ctx = llama_new_context_with_model(model, cparams);
    if (!ctx) {
        llama_model_free(model);
        if (err && err_size > 0) snprintf(err, err_size, "failed to create context");
        return nullptr;
    }

    TgChatModel* m = new TgChatModel();
    m->model = model;
    m->ctx = ctx;
    m->n_ctx = (int)llama_n_ctx(ctx);
    m->n_past = 0;
    m->n_vocab = (int)llama_n_vocab(model);
    return m;
}

void tgchat_free_model(TgChatModel* m) {
    if (!m) return;
    llama_free(m->ctx);
    llama_model_free(m->model);
    delete m;
}

int tgchat_n_ctx(const TgChatModel* m) {
    return m ? m->n_ctx : 0;
}

int tgchat_tokenize(TgChatModel* m, const char* text, int* tokens, int max_tokens, bool add_bos) {
    if (!m || !text || !tokens || max_tokens <= 0) return 0;
    return llama_tokenize(m->model, text, (int32_t)strlen(text), tokens, max_tokens, add_bos, false);
}

int tgchat_generate(TgChatModel* m, const char* prompt, char* out, int max_out,
                    float temp, int top_k, float top_p, int max_tokens,
                    float repeat_penalty, int repeat_last_n,
                    void (*callback)(const char* piece, void* user_data), void* user_data) {
    if (!m || !prompt || !out || max_out <= 0) return 0;

    std::vector<llama_token> prompt_tokens(m->n_ctx);
    int n_prompt = llama_tokenize(m->model, prompt, (int32_t)strlen(prompt),
                                  prompt_tokens.data(), (int32_t)prompt_tokens.size(), true, false);
    if (n_prompt < 0) return -1;
    prompt_tokens.resize(n_prompt);

    m->n_past = 0;
    if (!tgchat_eval(m, prompt_tokens)) return -2;

    llama_sampler* smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (repeat_penalty != 1.0f && repeat_last_n > 0) {
        llama_sampler_chain_add(smpl, llama_sampler_init_penalties(repeat_last_n, repeat_penalty, 0.0f, 0.0f));
    }
    llama_sampler_chain_add(smpl, llama_sampler_init_topk(top_k));
    llama_sampler_chain_add(smpl, llama_sampler_init_topp(top_p, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(temp));

    std::string result;
    llama_token id = 0;
    for (int i = 0; i < max_tokens; ++i) {
        id = llama_sampler_sample(smpl, m->ctx, -1);
        if (id == llama_token_eos(m->model)) break;

        char buf[64];
        int n = llama_token_to_piece(m->model, id, buf, sizeof(buf), 0, false);
        if (n > 0) {
            std::string piece(buf, n);
            result += piece;
            if (callback) callback(piece.c_str(), user_data);
        }

        std::vector<llama_token> batch = {id};
        if (!tgchat_eval(m, batch)) break;

        if ((int)result.size() >= max_out - 64) break;
    }

    llama_sampler_free(smpl);

    int copy_len = (int)result.size() < max_out - 1 ? (int)result.size() : max_out - 1;
    if (copy_len > 0) memcpy(out, result.data(), copy_len);
    out[copy_len] = '\0';
    return copy_len;
}

} // extern "C"
