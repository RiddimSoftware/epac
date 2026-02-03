import argparse
import torch
from transformers import AutoTokenizer, AutoModelForMaskedLM

def generate_text(model_path, prompt, length=50, temperature=1.0, top_p=0.9, repetition_penalty=1.5):
    """
    Generates text by iteratively appending [MASK] and predicting it.
    """
    print(f"Loading model from {model_path}...")
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    model = AutoModelForMaskedLM.from_pretrained(model_path)
    model.eval()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)

    current_text = prompt.strip()
    print(f"Generating starting from: \"{current_text}\"")

    special_tokens_ids = [tokenizer.cls_token_id, tokenizer.sep_token_id, tokenizer.pad_token_id, tokenizer.mask_token_id, tokenizer.unk_token_id]

    for i in range(length):
        # Provide multiple masks to give the model some "future" context
        mask_count = 5
        mask_str = " ".join([tokenizer.mask_token] * mask_count)
        
        # Truncate prompt if it's too long
        max_prompt_length = 512 - mask_count - 2
        inputs = tokenizer(current_text, 
                           add_special_tokens=True,
                           truncation=True, 
                           max_length=max_prompt_length,
                           return_tensors="pt").to(device)
        
        # Manually construct input: [CLS] + prompt_ids + [MASK]*5 + [SEP]
        input_ids = inputs["input_ids"]
        sep_token = torch.tensor([[tokenizer.sep_token_id]]).to(device)
        mask_tokens = torch.tensor([[tokenizer.mask_token_id] * mask_count]).to(device)
        
        # Remove original [SEP], add masks, add [SEP] back
        input_ids = torch.cat([input_ids[:, :-1], mask_tokens, sep_token], dim=1)
        attention_mask = torch.ones_like(input_ids).to(device)
        
        mask_token_index = torch.where(input_ids == tokenizer.mask_token_id)[1][0]

        with torch.no_grad():
            outputs = model(input_ids=input_ids, attention_mask=attention_mask)
            logits = outputs.logits
            
        mask_logits = logits[0, mask_token_index, :].clone()
        
        # Apply repetition penalty for recent tokens
        if repetition_penalty != 1.0:
            # Look at the last 30 tokens in the input
            recent_tokens = input_ids[0].tolist()
            for token_id in set(recent_tokens):
                if token_id not in special_tokens_ids:
                    if mask_logits[token_id] < 0:
                        mask_logits[token_id] *= repetition_penalty
                    else:
                        mask_logits[token_id] /= repetition_penalty

        # Filter special tokens
        for token_id in special_tokens_ids:
            mask_logits[token_id] = -float('Inf')
            
        # Apply temperature
        if temperature != 1.0:
            mask_logits = mask_logits / temperature
            
        # Top-p (nucleus) sampling
        sorted_logits, sorted_indices = torch.sort(mask_logits, descending=True)
        cumulative_probs = torch.cumsum(torch.nn.functional.softmax(sorted_logits, dim=-1), dim=-1)

        sorted_indices_to_remove = cumulative_probs > top_p
        sorted_indices_to_remove[..., 1:] = sorted_indices_to_remove[..., :-1].clone()
        sorted_indices_to_remove[..., 0] = 0

        indices_to_remove = sorted_indices[sorted_indices_to_remove]
        mask_logits[indices_to_remove] = -float('Inf')
        
        probs = torch.nn.functional.softmax(mask_logits, dim=-1)
        predicted_token_id = torch.multinomial(probs, 1)[0].item()
        
        predicted_token = tokenizer.convert_ids_to_tokens([predicted_token_id])[0]
        
        # Update current text
        if predicted_token.startswith("##"):
            current_text += predicted_token[2:]
        elif predicted_token in [".", ",", "!", "?", ":", ";"]:
            if current_text and current_text[-1] in [".", ",", "!", "?", ":", ";"]:
                # Don't repeat punctuation
                pass
            else:
                current_text += predicted_token
        else:
            current_text += " " + predicted_token
            
        # Stop if we hit a period and we've generated enough
        if predicted_token == "." and i > length // 2:
            break

    print(f"\nFinal generated text:\n{current_text}")
    return current_text


    print(f"\nFinal generated text:\n{current_text}")
    return current_text

def main():
    parser = argparse.ArgumentParser(description="Generate text using a finetuned MobileBERT model.")
    parser.add_argument("model_path", type=str, help="Path to the finetuned model directory")
    parser.add_argument("--prompt", type=str, default="Mr. Speaker, the government", help="Initial text to start generation")
    parser.add_argument("--length", type=int, default=50, help="Number of tokens to generate")
    parser.add_argument("--temperature", type=float, default=1.0, help="Sampling temperature")
    parser.add_argument("--top_p", type=float, default=0.9, help="Top-p sampling threshold")
    parser.add_argument("--repetition_penalty", type=float, default=1.2, help="Repetition penalty")

    args = parser.parse_args()

    generate_text(args.model_path, args.prompt, args.length, args.temperature, args.top_p, args.repetition_penalty)

if __name__ == "__main__":
    main()
